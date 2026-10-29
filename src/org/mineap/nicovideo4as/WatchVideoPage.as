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

        private static const WATCH_API_URL: String = "https://www.nicovideo.jp/api/watch/v3/";

        private static const WATCH_GUEST_API_URL: String = "https://www.nicovideo.jp/api/watch/v3_guest/";

        /** 後方互換用。直接URLとしては使わず参照用のみ。 */
        public static const WATCH_VIDEO_PAGE_URL: String = "https://www.nicovideo.jp/watch/";

        public static const WATCH_SUCCESS: String = "WatchSuccess";

        public static const WATCH_FAIL: String = "WatchFail";

        private var _videoId: String = "";

        private var _actionTrackId: String = "";

        /** v3_guest への切り替えを試行済みか */
        private var _guestTried: Boolean = false;

        /** 動画情報を v3_guest (未ログイン扱い) で取得したか */
        private var _guestFetched: Boolean = false;

        /**
         * user_session でログイン済みのとき、DMS(動画配信)用に別途取得したゲストの動画情報。
         * CDN の再生リストは domand_bid Cookie が無いと 403 になり、この Cookie は AIR の Cookie 管理を使うリクエスト
         * (= user_session を手動で付けられないリクエスト)でしか保存できない。そのため DMS セッションはゲスト用キーで作る。
         */
        private var _dmsJson: Object = null;
        private var _dmsActionTrackId: String = "";
        private var _loadingDmsGuest: Boolean = false;

        /** 直近のHTTPレスポンスステータス */
        private var _httpStatus: int = 0;

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

            this._actionTrackId = generateActionTrackId();
            this._guestTried = false;

            // ログイン済みなら /api/watch/v3、未ログイン(または v3 が拒否した場合)は /api/watch/v3_guest で取得する。
            // 未ログインで v3 を叩くと UNAUTHORIZED(400) が返るため、失敗時に errorHandler が v3_guest へ1回だけ切り替える。
            // 返却JSONの構造は両者とも {"data":{video, media.domand, client, ...}} で同一。
            this._watchLoader.addEventListener(Event.COMPLETE, completeEventHandler);
            this._watchLoader.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
            this._watchLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, errorHandler);
            this._watchLoader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, httpResponseHandler);
            loadWatchApi(WATCH_API_URL);
        }

        private function loadWatchApi(baseUrl: String): void {
            var watchURL: URLRequest = new URLRequest(
                baseUrl + encodeURIComponent(this._videoId) + "?actionTrackId=" + this._actionTrackId
            );
            watchURL.method = "GET";
            watchURL.followRedirects = true;
            watchURL.requestHeaders = [
                new URLRequestHeader("X-Frontend-Id", "6"),
                new URLRequestHeader("X-Frontend-Version", "0"),
                new URLRequestHeader("X-Niconico-Language", "ja-jp"),
                new URLRequestHeader("X-Request-With", "https://www.nicovideo.jp")
            ];
            // ログイン済み(user_session 取り込み済み)の v3 リクエストにだけセッションを付ける。ゲスト取得には付けない
            if (baseUrl == WATCH_API_URL) {
                Login.applySessionTo(watchURL);
            }
            this._guestFetched = baseUrl == WATCH_GUEST_API_URL;
            this._watchLoader.load(watchURL);
        }

        private function loadGuestForDms(): void {
            this._loadingDmsGuest = true;
            this._dmsActionTrackId = generateActionTrackId();
            var req: URLRequest = new URLRequest(
                WATCH_GUEST_API_URL + encodeURIComponent(this._videoId) + "?actionTrackId=" + this._dmsActionTrackId
            );
            req.method = "GET";
            req.followRedirects = true;
            req.requestHeaders = [
                new URLRequestHeader("X-Frontend-Id", "6"),
                new URLRequestHeader("X-Frontend-Version", "0"),
                new URLRequestHeader("X-Niconico-Language", "ja-jp"),
                new URLRequestHeader("X-Request-With", "https://www.nicovideo.jp")
            ];
            this._watchLoader.load(req);
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

            // DMS 用のゲスト情報の取得が終わった。取れなくても、ログイン側の情報で続行する
            if (this._loadingDmsGuest) {
                this._loadingDmsGuest = false;
                var guestObj: Object = createJsonObject(String(this._data));
                if (guestObj != null && guestObj.media != null && guestObj.media.domand != null) {
                    this._dmsJson = guestObj;
                }
                dispatchEvent(new Event(WATCH_SUCCESS));
                return;
            }

            // AIR の URLLoader は 4xx でも IO_ERROR にならず COMPLETE になることがある。
            // 未ログインで v3 が 400(UNAUTHORIZED) を返した場合などは、ここで v3_guest に切り替える。
            if (!this._guestTried && (this._httpStatus >= 400 || !hasVideoInfo(String(this._data)))) {
                this._guestTried = true;
                loadWatchApi(WATCH_GUEST_API_URL);
                return;
            }

            this._jsonObj = createJsonObject(String(this._data));
            if (this._jsonObj === null) {
                dispatchEvent(new ErrorEvent(WATCH_FAIL));
                return;
            }

            // 動画情報が無い(APIの構造変更等)場合は、後続で null 参照になる前にここで失敗として通知する
            if (this._jsonObj.video == null) {
                dispatchEvent(new ErrorEvent(WATCH_FAIL, false, false, "動画情報(video)が取得できませんでした"));
                return;
            }

            // v3 JSON API レスポンスは常に HTML5 相当
            this._isHTML5 = true;
            this._isFlash = false;

            // user_session でログイン済みの場合は、DMS 用にゲストの動画情報も取得してから成功を通知する
            if (!this._guestFetched && Login.manualUserSession != null) {
                loadGuestForDms();
                return;
            }

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
                        // HTML埋め込み server-response は {"data":{"metadata":..,"response":{video/owner/media/comment等}}} と
                        // 一段深くネストされている (v3 API直レスポンスの data は response の中身と同一構造)。
                        if (metaObj.data != null) {
                            if (metaObj.data.response != null) return metaObj.data.response;
                            return metaObj.data;
                        }
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
            var src: Object = dmsSource;
            if (src == null || src.media == null) {
                return false;
            }
            return src.media.domand != null;
        }

        /** DMS の情報源。user_session でログイン済みのときは、DMS 用に取得したゲストの動画情報。 */
        private function get dmsSource(): Object {
            return this._dmsJson != null ? this._dmsJson : this._jsonObj;
        }

        /** DMS 用の情報をゲストの動画情報から取っているか(画質はゲスト相当になる) */
        public function get dmsFromGuest(): Boolean {
            return this._dmsJson != null;
        }

        /** nvapi DMS セッション用アクセスキー */
        public function get domandAccessRightKey(): String {
            if (!isDms) return null;
            return String(dmsSource.media.domand.accessRightKey);
        }

        /** 利用可能な映像ストリーム候補 */
        public function get domandVideos(): Array {
            if (!isDms) return null;
            return dmsSource.media.domand.videos as Array;
        }

        /** 利用可能な音声ストリーム候補 */
        public function get domandAudios(): Array {
            if (!isDms) return null;
            return dmsSource.media.domand.audios as Array;
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

        /**
         * DMSセッション作成API (access-rights/hls) の actionTrackId に使うID。
         * accessRightKey (JWT) には watch API 取得時の actionTrackId が埋め込まれるため、
         * watch API に送ったものと同じ値を使う (別の値だと INVALID_PARAMETER になる)。
         */
        public function get watchTrackId(): String {
            if (this._dmsJson != null) return this._dmsActionTrackId;
            if (this._actionTrackId != "") return this._actionTrackId;
            if (_jsonObj == null || _jsonObj.client == null) return null;
            return String(_jsonObj.client.watchTrackId);
        }

        /**
         * 動画情報をゲストとして取得したか。
         * ゲスト取得時の accessRightKey はゲスト用なので、DMSセッション作成には Cookie を付けてはいけない。
         */
        public function get guestFetched(): Boolean {
            return this._guestFetched;
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

        /** レスポンスが動画情報(data.video)を含むか */
        private function hasVideoInfo(str: String): Boolean {
            var obj: Object = createJsonObject(str);
            return obj != null && obj.video != null;
        }

        private function errorHandler(event: ErrorEvent): void {
            // DMS 用のゲスト情報が取れなかった場合も、ログイン側の情報で続行する
            if (this._loadingDmsGuest) {
                this._loadingDmsGuest = false;
                dispatchEvent(new Event(WATCH_SUCCESS));
                return;
            }
            // 未ログイン等で v3 が拒否された場合は、v3_guest で1回だけ取り直す
            if (!this._guestTried) {
                this._guestTried = true;
                loadWatchApi(WATCH_GUEST_API_URL);
                return;
            }
            dispatchEvent(new ErrorEvent(WATCH_FAIL, false, false, event.text));
        }

        private function httpResponseHandler(event: HTTPStatusEvent): void {
            this._httpStatus = event.status;
            dispatchEvent(event);
        }

        public function close(): void {
            try {
                this._watchLoader.close();
            } catch (error: Error) {}
        }

    }
}
