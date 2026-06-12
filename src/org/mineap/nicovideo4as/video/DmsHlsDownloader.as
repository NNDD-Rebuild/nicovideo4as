package org.mineap.nicovideo4as.video {

import flash.desktop.NativeProcess;
import flash.desktop.NativeProcessStartupInfo;
import flash.events.NativeProcessExitEvent;
import flash.events.ErrorEvent;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.net.URLLoader;
import flash.net.URLLoaderDataFormat;
import flash.net.URLRequest;
import flash.net.URLStream;
import flash.utils.ByteArray;
import flash.utils.Dictionary;

/**
 * NicoNico DMS (Domand) の HLS ストリームを:
 *   master.m3u8 → video/audio variant → 暗号化セグメント個別保存
 *   → ローカル m3u8 生成 → ffmpeg (AES復号+mux) → output MP4
 * の順でダウンロードして 1 本の MP4 を生成する。
 * セグメントは最大 MAX_PARALLEL 本を並列ダウンロードする。
 *
 * Events dispatched:
 *   COMPLETE  - 完了、outputPath に MP4 が書かれた
 *   PROGRESS  - セグメント進捗 (ProgressEvent: bytesLoaded=current, bytesTotal=total)
 *   ERROR     - 失敗 (ErrorEvent: text にメッセージ)
 */
public class DmsHlsDownloader extends EventDispatcher {

    public static const COMPLETE:  String = "DmsHlsComplete";
    public static const PROGRESS:  String = "DmsHlsProgress";
    public static const ERROR:     String = "DmsHlsError";

    private static const MAX_PARALLEL: int = 8;

    // ---- 公開プロパティ ----
    private var _outputPath: String;

    public function get outputPath(): String { return _outputPath; }

    /** 外部からログ出力を受け取るコールバック。null可。 */
    public var logCallback: Function = null;
    private function log(msg: String): void {
        if (logCallback != null) logCallback("[DmsHls] " + msg);
    }

    // ---- 内部状態 ----
    private var _masterUrl:         String;
    private var _saveDir:           File;

    private var _videoVariantUrl:   String;
    private var _audioVariantUrl:   String;

    private var _videoKeyUrl:       String;
    private var _videoIv:           ByteArray;
    private var _videoKey:          ByteArray;
    private var _videoInitUrl:      String;
    private var _videoSegUrls:      Vector.<String>;

    private var _audioKeyUrl:       String;
    private var _audioIv:           ByteArray;
    private var _audioKey:          ByteArray;
    private var _audioInitUrl:      String;
    private var _audioSegUrls:      Vector.<String>;

    // temp file paths
    private var _videoSegPaths:     Vector.<String>;
    private var _audioSegPaths:     Vector.<String>;
    private var _videoInitPath:     String;
    private var _audioInitPath:     String;
    private var _videoKeyPath:      String;
    private var _audioKeyPath:      String;
    private var _videoM3u8Path:     String;
    private var _audioM3u8Path:     String;

    private var _downloadingVideo:  Boolean = true;

    // 並列DL用
    private var _streams:           Dictionary;  // URLStream -> segIdx
    private var _pendingBuffers:    Dictionary;  // segIdx -> ByteArray
    private var _nextWriteIdx:      int = 0;
    private var _activeCount:       int = 0;
    private var _nextLaunchIdx:     int = 0;
    private var _totalSegs:         int = 0;
    private var _writtenCount:      int = 0;

    private var _loader:            URLLoader;
    private var _process:           NativeProcess;

    // ---- エントリポイント ----

    public function startDownload(masterUrl: String, saveDir: File, fileName: String = "nndd_dms"): void {
        log("startDownload: " + masterUrl.substring(0, 80));
        _masterUrl     = masterUrl;
        _saveDir       = saveDir;
        _outputPath    = saveDir.nativePath + "\\" + fileName + ".mp4";

        _videoInitPath = saveDir.nativePath + "\\_dms_video_init.bin";
        _audioInitPath = saveDir.nativePath + "\\_dms_audio_init.bin";
        _videoKeyPath  = saveDir.nativePath + "\\_dms_video_key.bin";
        _audioKeyPath  = saveDir.nativePath + "\\_dms_audio_key.bin";
        _videoM3u8Path = saveDir.nativePath + "\\_dms_video.m3u8";
        _audioM3u8Path = saveDir.nativePath + "\\_dms_audio.m3u8";

        deleteIfExists(_videoInitPath);
        deleteIfExists(_audioInitPath);
        deleteIfExists(_videoKeyPath);
        deleteIfExists(_audioKeyPath);
        deleteIfExists(_videoM3u8Path);
        deleteIfExists(_audioM3u8Path);
        deleteIfExists(_outputPath);

        log("fetchText master.m3u8 開始");
        fetchText(_masterUrl, onMasterLoaded);
    }

    // ---- Step 1: master.m3u8 ----

    private function onMasterLoaded(text: String): void {
        log("onMasterLoaded: " + text.substring(0, 200));
        parseMaster(text, _masterUrl);
    }

    private function parseMaster(text: String, baseUrl: String): void {
        var lines: Array = text.split(/\r?\n/);
        var i: int = 0;
        while (i < lines.length) {
            var line: String = trim(lines[i]);
            if (line.indexOf("#EXT-X-MEDIA") == 0 && line.indexOf("TYPE=AUDIO") >= 0) {
                var au: Array = /URI="([^"]+)"/.exec(line);
                if (au) _audioVariantUrl = resolveUrl(baseUrl, au[1]);
            } else if (line.indexOf("#EXT-X-STREAM-INF") == 0) {
                i++;
                if (i < lines.length) {
                    var vl: String = trim(lines[i]);
                    if (vl.length > 0 && vl.charAt(0) != '#' && _videoVariantUrl == null) {
                        _videoVariantUrl = resolveUrl(baseUrl, vl);
                    }
                }
            }
            i++;
        }
        if (_videoVariantUrl == null) {
            fail("master.m3u8 から video variant URL が見つかりません");
            return;
        }
        log("video variant URL: " + _videoVariantUrl.substring(0, 80));
        fetchText(_videoVariantUrl, onVideoVariantLoaded);
    }

    // ---- Step 2: video variant ----

    private function onVideoVariantLoaded(text: String): void {
        log("onVideoVariantLoaded: " + text.length + " chars");
        var parsed: Object = parseVariant(text, _videoVariantUrl);
        _videoKeyUrl  = parsed.keyUrl;
        _videoIv      = parsed.iv;
        _videoInitUrl = parsed.initUrl;
        _videoSegUrls = parsed.segments;

        if (_audioVariantUrl) {
            fetchText(_audioVariantUrl, onAudioVariantLoaded);
        } else {
            if (_videoKeyUrl) fetchBinary(_videoKeyUrl, onVideoKeyLoaded);
            else              startVideoDownload();
        }
    }

    // ---- Step 3: audio variant ----

    private function onAudioVariantLoaded(text: String): void {
        var parsed: Object = parseVariant(text, _audioVariantUrl);
        _audioKeyUrl  = parsed.keyUrl;
        _audioIv      = parsed.iv;
        _audioInitUrl = parsed.initUrl;
        _audioSegUrls = parsed.segments;

        if (_videoKeyUrl) fetchBinary(_videoKeyUrl, onVideoKeyLoaded);
        else              startVideoDownload();
    }

    // ---- Step 4: AES keys ----

    private function onVideoKeyLoaded(data: ByteArray): void {
        _videoKey = data;
        if (_audioKeyUrl) fetchBinary(_audioKeyUrl, onAudioKeyLoaded);
        else              startVideoDownload();
    }

    private function onAudioKeyLoaded(data: ByteArray): void {
        _audioKey = data;
        startVideoDownload();
    }

    // ---- Step 5/6: segments (parallel) ----

    private function startVideoDownload(): void {
        log("startVideoDownload: segs=" + (_videoSegUrls ? _videoSegUrls.length : 0));
        _downloadingVideo = true;
        _videoSegPaths = new Vector.<String>();
        initParallelState(_videoSegUrls, _videoInitUrl);
        if (_videoKey != null) writeBytes(_videoKey, _videoKeyPath);
        if (_videoInitUrl != null) {
            fetchInitSegment(_videoInitUrl, _videoInitPath, function(): void {
                launchParallel();
            });
        } else {
            launchParallel();
        }
    }

    private function startAudioDownload(): void {
        log("startAudioDownload: segs=" + (_audioSegUrls ? _audioSegUrls.length : 0));
        _downloadingVideo = false;
        _audioSegPaths = new Vector.<String>();
        var segs: Vector.<String> = _audioSegUrls ? _audioSegUrls : new Vector.<String>();
        initParallelState(segs, _audioInitUrl);
        if (_audioKey != null) writeBytes(_audioKey, _audioKeyPath);
        if (_audioInitUrl != null) {
            fetchInitSegment(_audioInitUrl, _audioInitPath, function(): void {
                launchParallel();
            });
        } else {
            launchParallel();
        }
    }

    private function initParallelState(segs: Vector.<String>, initUrl: String): void {
        _streams        = new Dictionary();
        _pendingBuffers = new Dictionary();
        _nextWriteIdx   = 0;
        _nextLaunchIdx  = 0;
        _activeCount    = 0;
        _writtenCount   = 0;
        _totalSegs      = segs ? segs.length : 0;
    }

    private function fetchInitSegment(url: String, path: String, onDone: Function): void {
        var s: URLStream = new URLStream();
        s.addEventListener(Event.COMPLETE, function(e: Event): void {
            s.removeEventListener(Event.COMPLETE, arguments.callee);
            var raw: ByteArray = new ByteArray();
            s.readBytes(raw, 0, s.bytesAvailable);
            writeBytes(raw, path);
            onDone();
        });
        s.addEventListener(IOErrorEvent.IO_ERROR, function(e: IOErrorEvent): void {
            fail("init segment DL失敗: " + e.text);
        });
        s.load(new URLRequest(url));
    }

    private function launchParallel(): void {
        var segs: Vector.<String> = currentSegs();
        while (_activeCount < MAX_PARALLEL && _nextLaunchIdx < segs.length) {
            var idx: int = _nextLaunchIdx++;
            _activeCount++;
            launchSegment(idx, segs[idx]);
        }
        if (_totalSegs == 0) {
            onAllSegsDone();
        }
    }

    private function launchSegment(idx: int, url: String): void {
        var s: URLStream = new URLStream();
        _streams[s] = idx;
        s.addEventListener(Event.COMPLETE, onSegLoaded);
        s.addEventListener(IOErrorEvent.IO_ERROR, onStreamError);
        s.load(new URLRequest(url));
    }

    private function onSegLoaded(event: Event): void {
        var s: URLStream = event.target as URLStream;
        s.removeEventListener(Event.COMPLETE, onSegLoaded);
        s.removeEventListener(IOErrorEvent.IO_ERROR, onStreamError);

        var idx: int = _streams[s];
        delete _streams[s];
        _activeCount--;

        var raw: ByteArray = new ByteArray();
        s.readBytes(raw, 0, s.bytesAvailable);

        _pendingBuffers[idx] = raw;
        flushPending();

        var segs: Vector.<String> = currentSegs();
        if (_nextLaunchIdx < segs.length) {
            var nextIdx: int = _nextLaunchIdx++;
            _activeCount++;
            launchSegment(nextIdx, segs[nextIdx]);
        }

        if (_activeCount == 0 && _nextLaunchIdx >= segs.length) {
            onAllSegsDone();
        }
    }

    private function flushPending(): void {
        while (_pendingBuffers[_nextWriteIdx] != null) {
            var data: ByteArray = _pendingBuffers[_nextWriteIdx] as ByteArray;
            delete _pendingBuffers[_nextWriteIdx];

            var suffix: String = _downloadingVideo ? "_v" : "_a";
            var segPath: String = _saveDir.nativePath + "\\_dms" + suffix + "_seg" + _nextWriteIdx + ".bin";
            writeBytes(data, segPath);

            if (_downloadingVideo) _videoSegPaths.push(segPath);
            else                   _audioSegPaths.push(segPath);

            dispatchEvent(new ProgressEvent(PROGRESS, false, false, _nextWriteIdx, _totalSegs));
            _writtenCount++;
            _nextWriteIdx++;
        }
    }

    private function onAllSegsDone(): void {
        log("onAllSegsDone: downloadingVideo=" + _downloadingVideo);
        if (_downloadingVideo) {
            buildAndWriteM3u8(_videoM3u8Path, _videoInitPath, _videoKeyPath, _videoIv, _videoSegPaths);
            if (_audioVariantUrl) startAudioDownload();
            else runFfmpeg();
        } else {
            buildAndWriteM3u8(_audioM3u8Path, _audioInitPath, _audioKeyPath, _audioIv, _audioSegPaths);
            runFfmpeg();
        }
    }

    private function onStreamError(event: IOErrorEvent): void {
        var s: URLStream = event.target as URLStream;
        s.removeEventListener(Event.COMPLETE, onSegLoaded);
        s.removeEventListener(IOErrorEvent.IO_ERROR, onStreamError);
        fail("セグメントダウンロード失敗: " + event.text);
    }

    private function currentSegs(): Vector.<String> {
        return _downloadingVideo ? _videoSegUrls : (_audioSegUrls ? _audioSegUrls : new Vector.<String>());
    }

    // ---- Step 9: ffmpeg mux + AES復号 ----

    private function runFfmpeg(): void {
        log("runFfmpeg 開始");
        if (!NativeProcess.isSupported) {
            fail("NativeProcess非対応。NNDD-app.xmlにextendedDesktopが必要です。");
            return;
        }

        var ffmpeg: File = findFfmpeg();
        if (ffmpeg == null) {
            fail("ffmpegが見つかりません。インストール後にPATHへ追加してください。");
            return;
        }

        var info: NativeProcessStartupInfo = new NativeProcessStartupInfo();
        info.executable = ffmpeg;
        var args: Vector.<String> = new Vector.<String>();
        args.push("-y");
        args.push("-protocol_whitelist"); args.push("file,crypto,data,concat");
        args.push("-allowed_extensions");  args.push("ALL");
        args.push("-i"); args.push(_videoM3u8Path);
        if (_audioVariantUrl) {
            args.push("-allowed_extensions"); args.push("ALL");
            args.push("-i"); args.push(_audioM3u8Path);
        }
        args.push("-c:v"); args.push("copy");
        args.push("-c:a"); args.push("copy");
        args.push(_outputPath);
        info.arguments = args;

        log("ffmpeg args: " + args.join(" "));
        _process = new NativeProcess();
        _process.addEventListener(NativeProcessExitEvent.EXIT, onFfmpegExit);
        try {
            _process.start(info);
        } catch (e: Error) {
            fail("ffmpeg起動失敗: " + e.message);
        }
    }

    private function onFfmpegExit(event: NativeProcessExitEvent): void {
        _process.removeEventListener(NativeProcessExitEvent.EXIT, onFfmpegExit);
        log("ffmpeg exit: " + event.exitCode);
        if (event.exitCode == 0) {
            cleanupTempFiles();
            dispatchEvent(new Event(COMPLETE));
        } else {
            fail("ffmpeg 失敗 exitCode=" + event.exitCode);
        }
    }

    private function cleanupTempFiles(): void {
        if (_videoSegPaths) {
            for each (var vp: String in _videoSegPaths) deleteIfExists(vp);
        }
        if (_audioSegPaths) {
            for each (var ap: String in _audioSegPaths) deleteIfExists(ap);
        }
        deleteIfExists(_videoInitPath);
        deleteIfExists(_audioInitPath);
        deleteIfExists(_videoKeyPath);
        deleteIfExists(_audioKeyPath);
        deleteIfExists(_videoM3u8Path);
        deleteIfExists(_audioM3u8Path);
    }

    // ---- Helpers ----

    private function writeBytes(data: ByteArray, path: String): void {
        var fs: FileStream = new FileStream();
        fs.open(new File(path), FileMode.WRITE);
        data.position = 0;
        fs.writeBytes(data);
        fs.close();
    }

    private function buildAndWriteM3u8(m3u8Path: String, initPath: String,
                                        keyPath: String, iv: ByteArray,
                                        segPaths: Vector.<String>): void {
        var lines: Array = [];
        lines.push("#EXTM3U");
        lines.push("#EXT-X-VERSION:7");
        lines.push("#EXT-X-TARGETDURATION:10");
        lines.push("#EXT-X-MEDIA-SEQUENCE:0");
        // EXT-X-MAP must come before EXT-X-KEY so init segment is not decrypted
        var inf: File = new File(initPath);
        if (inf.exists) lines.push('#EXT-X-MAP:URI="' + inf.name + '"');
        var kf: File = new File(keyPath);
        if (kf.exists) {
            var keyLine: String = '#EXT-X-KEY:METHOD=AES-128,URI="' + kf.name + '"';
            if (iv != null && iv.length >= 16) keyLine += ",IV=0x" + bytesToHex(iv);
            lines.push(keyLine);
        }
        for each (var seg: String in segPaths) {
            lines.push("#EXTINF:5.000,");
            lines.push(new File(seg).name);
        }
        lines.push("#EXT-X-ENDLIST");
        var fs: FileStream = new FileStream();
        fs.open(new File(m3u8Path), FileMode.WRITE);
        fs.writeUTFBytes(lines.join("\n"));
        fs.close();
        log("m3u8 written: " + m3u8Path + " (" + segPaths.length + " segs)");
    }

    private function bytesToHex(ba: ByteArray): String {
        var hex: String = "";
        for (var i: int = 0; i < ba.length; i++) {
            var b: String = ba[i].toString(16);
            if (b.length < 2) b = "0" + b;
            hex += b;
        }
        return hex;
    }

    // ---- Utilities ----

    private function parseVariant(text: String, baseUrl: String): Object {
        var keyUrl:   String  = null;
        var iv:       ByteArray = null;
        var initUrl:  String  = null;
        var segs:     Vector.<String> = new Vector.<String>();

        for each (var rawLine: String in text.split(/\r?\n/)) {
            var line: String = trim(rawLine);
            if (line.length == 0) continue;

            if (line.indexOf("#EXT-X-KEY") == 0) {
                var ku: Array = /URI="([^"]+)"/.exec(line);
                if (ku) keyUrl = resolveUrl(baseUrl, ku[1]);
                var ivm: Array = /IV=0x([0-9A-Fa-f]+)/i.exec(line);
                if (ivm) iv = hexToBytes(ivm[1]);
            } else if (line.indexOf("#EXT-X-MAP") == 0) {
                var mu: Array = /URI="([^"]+)"/.exec(line);
                if (mu) initUrl = resolveUrl(baseUrl, mu[1]);
            } else if (line.charAt(0) != '#') {
                segs.push(resolveUrl(baseUrl, line));
            }
        }
        return { keyUrl: keyUrl, iv: iv, initUrl: initUrl, segments: segs };
    }

    private function resolveUrl(base: String, rel: String): String {
        if (rel.indexOf("http") == 0) return rel;
        var qIdx: int = base.indexOf("?");
        var basePath: String = (qIdx >= 0) ? base.substring(0, qIdx) : base;
        var lastSlash: int = basePath.lastIndexOf("/");
        return (lastSlash >= 0) ? basePath.substring(0, lastSlash + 1) + rel : rel;
    }

    private function hexToBytes(hex: String): ByteArray {
        while (hex.length < 32) hex = "0" + hex;
        hex = hex.substring(hex.length - 32);
        var ba: ByteArray = new ByteArray();
        for (var i: int = 0; i < 32; i += 2) {
            ba.writeByte(parseInt(hex.substring(i, i + 2), 16));
        }
        return ba;
    }

    private function trim(s: String): String {
        return s.replace(/^\s+|\s+$/g, "");
    }

    private function deleteIfExists(path: String): void {
        try {
            var f: File = new File(path);
            if (f.exists) f.deleteFile();
        } catch (e: Error) {}
    }

    // ---- HTTP helpers ----

    private function fetchText(url: String, callback: Function): void {
        log("fetchText: " + url.substring(0, 80));
        _loader = new URLLoader();
        _loader.dataFormat = URLLoaderDataFormat.TEXT;
        _loader.addEventListener(Event.COMPLETE, function(e: Event): void {
            _loader.removeEventListener(Event.COMPLETE, arguments.callee);
            log("fetchText complete: " + url.substring(0, 60));
            callback(String(_loader.data));
        });
        _loader.addEventListener(IOErrorEvent.IO_ERROR, function(e: IOErrorEvent): void {
            fail("テキスト取得失敗 " + url + ": " + e.text);
        });
        _loader.addEventListener("securityError", function(e: Event): void {
            fail("セキュリティエラー(fetchText) " + url + ": " + e.toString());
        });
        _loader.load(new URLRequest(url));
    }

    private function fetchBinary(url: String, callback: Function): void {
        log("fetchBinary: " + url.substring(0, 80));
        _loader = new URLLoader();
        _loader.dataFormat = URLLoaderDataFormat.BINARY;
        _loader.addEventListener(Event.COMPLETE, function(e: Event): void {
            _loader.removeEventListener(Event.COMPLETE, arguments.callee);
            log("fetchBinary complete: " + url.substring(0, 60));
            callback(_loader.data as ByteArray);
        });
        _loader.addEventListener(IOErrorEvent.IO_ERROR, function(e: IOErrorEvent): void {
            fail("バイナリ取得失敗 " + url + ": " + e.text);
        });
        _loader.addEventListener("securityError", function(e: Event): void {
            fail("セキュリティエラー(fetchBinary) " + url + ": " + e.toString());
        });
        _loader.load(new URLRequest(url));
    }

    // ---- ffmpeg location ----

    private static function findFfmpeg(): File {
        var candidates: Array = [
            "C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe",
            "C:\\Program Files (x86)\\ffmpeg\\bin\\ffmpeg.exe",
            "C:\\ffmpeg\\bin\\ffmpeg.exe",
            "C:\\ffmpeg\\ffmpeg.exe",
            "C:\\ProgramData\\chocolatey\\bin\\ffmpeg.exe",
        ];
        try {
            candidates.push(File.userDirectory.nativePath + "\\scoop\\shims\\ffmpeg.exe");
        } catch (e: Error) {}

        for each (var p: String in candidates) {
            var f: File = new File(p);
            if (f.exists) return f;
        }
        return null;
    }

    private function fail(msg: String): void {
        dispatchEvent(new ErrorEvent(ERROR, false, false, msg));
    }
}
}
