package org.mineap.nicovideo4as.loader.api {
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;

    public class ApiDmsAccess extends URLLoader {
        private static const BASE_URL: String =
            "https://nvapi.nicovideo.jp/v1/watch/";

        /**
         * @param actionTrackId watchページ取得時にサーバーが発行した watchTrackId
         *   (WatchVideoPage.watchTrackId)。クライアント側で自前生成したIDを使うと
         *   INVALID_PARAMETER(400)になる。
         */
        public function createDmsSession(
            videoId: String,
            accessRightKey: String,
            videoStreamId: String,
            audioStreamId: String,
            actionTrackId: String
        ): void {
            var req: URLRequest = new URLRequest(
                BASE_URL + encodeURIComponent(videoId) + "/access-rights/hls?actionTrackId=" + actionTrackId
            );
            req.method = "POST";
            req.data = JSON.stringify({"outputs": [[videoStreamId, audioStreamId]]});
            req.requestHeaders = [
                new URLRequestHeader("X-Access-Right-Key", accessRightKey),
                // 実ブラウザはこのAPI呼び出し時 "nicovideo" 固定文字列を送る
                // (視聴ログ用heartbeat呼び出し時のみ Referer相当のURLを送る)。
                new URLRequestHeader("X-Request-With", "nicovideo"),
                new URLRequestHeader("X-Frontend-Id", "6"),
                new URLRequestHeader("X-Frontend-Version", "0"),
                new URLRequestHeader("Content-Type", "application/json"),
                new URLRequestHeader("Accept", "application/json;charset=utf-8")
            ];
            this.load(req);
        }
    }
}
