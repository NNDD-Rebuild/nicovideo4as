package org.mineap.nicovideo4as.loader.api {
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;

    public class ApiDmsAccess extends URLLoader {
        private static const BASE_URL: String =
            "https://nvapi.nicovideo.jp/v1/watch/";

        public function createDmsSession(
            videoId: String,
            accessRightKey: String,
            videoStreamId: String,
            audioStreamId: String
        ): void {
            var actionTrackId: String = generateActionTrackId();
            var req: URLRequest = new URLRequest(
                BASE_URL + encodeURIComponent(videoId) + "/access-rights/hls?actionTrackId=" + actionTrackId
            );
            req.method = "POST";
            req.data = JSON.stringify({"outputs": [[videoStreamId, audioStreamId]]});
            req.requestHeaders = [
                new URLRequestHeader("X-Access-Right-Key", accessRightKey),
                new URLRequestHeader("X-Request-With", "https://www.nicovideo.jp"),
                new URLRequestHeader("X-Frontend-Id", "6"),
                new URLRequestHeader("X-Frontend-Version", "0"),
                new URLRequestHeader("X-Niconico-Language", "ja-jp"),
                new URLRequestHeader("Content-Type", "application/json"),
                new URLRequestHeader("Accept", "application/json")
            ];
            this.load(req);
        }

        private function generateActionTrackId(): String {
            const chars: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
            var rand: String = "";
            for (var i: int = 0; i < 10; i++) {
                rand += chars.charAt(int(Math.random() * chars.length));
            }
            return rand + "_" + new Date().getTime().toString();
        }
    }
}
