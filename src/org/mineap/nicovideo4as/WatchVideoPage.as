package org.mineap.nicovideo4as {
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.HTTPStatusEvent;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;

    [Event(name="watchSuccess", type="org.mineap.nicovideo4as.WatchVideoPage")]
    [Event(name="watchFail", type="org.mineap.nicovideo4as.WatchVideoPage")]
    [Event(name="httpResponseStatus", type="HTTPStatusEvent")]

    /**
     *
     * @author shiraminekeisuke(MineAP)
     *
     */ public class WatchVideoPage extends EventDispatcher {

        private var _watchLoader: URLLoader;

        private static const harmful: String = "watch_harmful=1";

        /** 後方互換用。直接URLとしては使わず参照用のみ。 */
        public static const WATCH_VIDEO_PAGE_URL: String = "https://www.nicovideo.jp/watch/";

        private static const WATCH_API_URL: String = "https://www.nicovideo.jp/api/watch/v3/";

        public static const WATCH_SUCCESS: String = "WatchSuccess";

        public static const WATCH_FAIL: String = "WatchFail";

        private var _videoId: String = "";

        private var _data: Object = "";

        private var _jsonObj: Object = null;

        private var _isHTML5: Boolean = false;
        private var _isFlash: Boolean = false;

        public function WatchVideoPage() {
            this._watchLoader = new URLLoader();
        }

        /**
         * @param videoId 開く動画のID
         * @param watchHarmful 有害動画を強制的に開くかどうか（v3 APIでは未使用）
         */
        public function watchVideo(videoId: String, watchHarmful: Boolean): void {
            this._videoId = videoId;

            var actionTrackId: String = generateActionTrackId();
            var mUrl: String = WATCH_API_URL + encodeURIComponent(videoId) + "?actionTrackId=" + actionTrackId;

            var watchURL: URLRequest = new URLRequest(mUrl);
            watchURL.method = "GET";
            watchURL.followRedirects = true;
            watchURL.requestHeaders = [
                new URLRequestHeader("X-Frontend-Id", "6"),
                new URLRequestHeader("X-Frontend-Version", "0"),
                new URLRequestHeader("X-Niconico-Language", "ja-jp"),
                new URLRequestHeader("X-Request-With", "https://www.nicovideo.jp")
            ];

            this._watchLoader.addEventListener(Event.COMPLETE, completeEventHandler);
            this._watchLoader.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
            this._watchLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, errorHandler);
            this._watchLoader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, httpResponseHandler);
            this._watchLoader.load(watchURL);
        }

        private function generateActionTrackId(): String {
            const chars: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
            var rand: String = "";
            for (var i: int = 0; i < 10; i++) {
                rand += chars.charAt(int(Math.random() * chars.length));
            }
            return rand + "_" + new Date().getTime().toString();
        }

        public function getVideoId(): String {
            if (this._isHTML5) {
                return this._jsonObj.video.id;
            }
            return this._videoId;
        }

        public function getDescription(): String {
            if (this._isHTML5) {
                return this._jsonObj.video.description || "";
            }
            return "";
        }

        public function getPubUserId(): String {
            if (this._isHTML5) {
                if (this._jsonObj.owner != null) {
                    return String(this._jsonObj.owner.id);
                }
            }
            return null;
        }

        public function getPubUserIconUrl(): String {
            if (this._isHTML5) {
                if (this._jsonObj.owner != null) {
                    // v3 API は iconUrl (小文字 u)
                    return this._jsonObj.owner.iconUrl;
                }
            }
            return null;
        }

        public function getPubUserName(): String {
            if (this._isHTML5) {
                if (this._jsonObj.owner != null) {
                    return this._jsonObj.owner.nickname;
                }
            }
            return null;
        }

        public function getChannel(): String {
            if (this._isHTML5) {
                if (this._jsonObj.channel != null) {
                    return this._jsonObj.channel.id;
                }
            }
            return null;
        }

        public function getChannelIconUrl(): String {
            if (this._isHTML5) {
                if (this._jsonObj.channel != null) {
                    return this._jsonObj.channel.thumbnail
                        ? this._jsonObj.channel.thumbnail.url
                        : null;
                }
            }
            return null;
        }

        public function getChannelName(): String {
            if (this._isHTML5) {
                if (this._jsonObj.channel != null) {
                    return this._jsonObj.channel.name;
                }
            }
            return null;
        }

        public function checkHarmful(): Boolean {
            if (this._isHTML5) {
                return Boolean(this._jsonObj.video.isR18);
            }
            return false;
        }

        public function get audioDownloadUrl(): String {
            return null;
        }

        private function completeEventHandler(event: Event): void {
            this._data = this._watchLoader.data;

            this._jsonObj = createJsonObject(String(this._data));
            if (this._jsonObj === null) {
                dispatchEvent(new ErrorEvent(WATCH_FAIL));
                return;
            }

            // v3 JSON API レスポンスは常に HTML5 相当
            this._isHTML5 = true;
            this._isFlash = false;

            dispatchEvent(new Event(WATCH_SUCCESS));
        }

        /**
         * レスポンス文字列から動画情報JSONオブジェクトを生成する。
         *
         * 優先順位:
         *   1. /api/watch/v3 JSON レスポンス: {"data": {...}}
         *   2. HTML fallback: <meta name="server-response" content='...'>
         *   3. HTML fallback: data-api-data 属性
         */
        private function createJsonObject(str: String): Object {
            if (str == null) {
                return null;
            }

            // 1. /api/watch/v3 JSON レスポンス
            try {
                var wrapper: Object = JSON.parse(str);
                if (wrapper != null && wrapper.data != null) {
                    return wrapper.data;
                }
            } catch (e1: Error) { /* not JSON or missing data field */ }

            // 2. <meta name="server-response" content='...'> (属性順序不問)
            var metaPattern: RegExp = /<meta\b[^>]*\bname=['"]server-response['"][^>]*>/i;
            var metaBlockMatch: Array = metaPattern.exec(str);
            if (metaBlockMatch) {
                var metaTag: String = metaBlockMatch[0];
                var contentPattern: RegExp = /\bcontent=(['"])([\s\S]*?)\1/i;
                var contentMatch: Array = contentPattern.exec(metaTag);
                if (contentMatch && contentMatch[2]) {
                    try {
                        var decoded: String = htmlDecode(contentMatch[2]);
                        var metaObj: Object = JSON.parse(decoded);
                        if (metaObj.data != null) return metaObj.data;
                        if (metaObj.response != null) return metaObj.response;
                        return metaObj;
                    } catch (e2: Error) {}
                }
            }

            // 3. data-api-data 属性 (シングル・ダブルクォート両対応)
            var divPattern: RegExp = /data-api-data=(['"])([\s\S]+?)\1/i;
            var divMatch: Array = divPattern.exec(str);
            if (divMatch && divMatch[2]) {
                try {
                    var decoded2: String = htmlDecode(divMatch[2]);
                    var divObj: Object = JSON.parse(decoded2);
                    if (divObj.data != null) return divObj.data;
                    return divObj;
                } catch (e3: Error) {}
            }

            return null;
        }

        private function htmlDecode(s: String): String {
            return s
                .replace(/&quot;/g, '"')
                .replace(/&#39;/g, "'")
                .replace(/&lt;/g, "<")
                .replace(/&gt;/g, ">")
                .replace(/&amp;/g, "&");
        }

        public function get data(): Object {
            return this._data;
        }

        public function get jsonData(): Object {
            return this._jsonObj;
        }

        /** DMC セッション情報が利用可能か（media.delivery.movie.session が存在する場合） */
        public function get isDmc(): Boolean {
            if (this._jsonObj == null || this._jsonObj.media == null) {
                return false;
            }
            var delivery: Object = this._jsonObj.media.delivery;
            if (delivery == null) return false;
            var movie: Object = delivery.movie;
            return movie != null && movie.session != null;
        }

        /** DMS（新配信システム、HLS）か。AS3では直接ダウンロード不可。 */
        public function get isDms(): Boolean {
            if (this._jsonObj == null || this._jsonObj.media == null) {
                return false;
            }
            return this._jsonObj.media.domand != null;
        }

        /** nvapi DMS セッション用アクセスキー */
        public function get domandAccessRightKey(): String {
            if (!isDms) return null;
            return String(_jsonObj.media.domand.accessRightKey);
        }

        /** 利用可能な映像ストリーム候補 */
        public function get domandVideos(): Array {
            if (!isDms) return null;
            return _jsonObj.media.domand.videos as Array;
        }

        /** 利用可能な音声ストリーム候補 */
        public function get domandAudios(): Array {
            if (!isDms) return null;
            return _jsonObj.media.domand.audios as Array;
        }

        /**
         * DMC セッション情報オブジェクトを返す。
         * DmcInfoAnalyzer.analyze() の引数として使う。
         * _jsonObj 全体を渡す（media.delivery.movie.session パスは Analyzer 側が解決）。
         */
        public function get dmcInfo(): Object {
            if (!this.isDmc) {
                return null;
            }
            return this._jsonObj;
        }

        public function get smileInfo(): Object {
            if (this._isHTML5 && this._jsonObj.video != null) {
                return this._jsonObj.video.smileInfo;
            }
            return null;
        }

        public function get isPremium(): Boolean {
            if (this._isHTML5 && this._jsonObj.viewer != null) {
                return Boolean(this._jsonObj.viewer.isPremium);
            }
            return false;
        }

        public function get channelId(): String {
            if (this._jsonObj != null && this._jsonObj.channel != null) {
                return this._jsonObj.channel.id;
            }
            return null;
        }

        public function get isHTML5(): Boolean {
            return this._isHTML5;
        }

        public function get isFlash(): Boolean {
            return this._isFlash;
        }

        // ---- nvComment 関連ゲッター ----

        /** nvcomment API 用 threadKey。CommentLoader.getNvComment() に渡す。 */
        public function get nvCommentThreadKey(): String {
            if (_jsonObj == null || _jsonObj.comment == null) return null;
            var nv: Object = _jsonObj.comment.nvComment;
            return nv ? String(nv.threadKey) : null;
        }

        /**
         * nvcomment API 用パラメータ。
         * @return {language: String, targets: Array} または null
         */
        public function get nvCommentParams(): Object {
            if (_jsonObj == null || _jsonObj.comment == null) return null;
            var nv: Object = _jsonObj.comment.nvComment;
            return nv ? nv.params : null;
        }

        /** nvcomment サーバー URL。デフォルト: https://nvcomment.nicovideo.jp */
        public function get nvCommentServerUrl(): String {
            if (_jsonObj == null || _jsonObj.comment == null) {
                return "https://nvcomment.nicovideo.jp";
            }
            var nv: Object = _jsonObj.comment.nvComment;
            if (nv && nv.server) {
                return String(nv.server);
            }
            return "https://nvcomment.nicovideo.jp";
        }

        /** コメント投稿用ユーザーキー */
        public function get userKey(): String {
            if (_jsonObj == null || _jsonObj.comment == null) return "";
            var keys: Object = _jsonObj.comment.keys;
            return keys && keys.userKey ? String(keys.userKey) : "";
        }

        private function errorHandler(event: ErrorEvent): void {
            dispatchEvent(new ErrorEvent(WATCH_FAIL, false, false, event.text));
        }

        private function httpResponseHandler(event: HTTPStatusEvent): void {
            dispatchEvent(event);
        }

        public function close(): void {
            try {
                this._watchLoader.close();
            } catch (error: Error) {}
        }

    }
}
