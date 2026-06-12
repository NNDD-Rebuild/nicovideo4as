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
            var req: URLRequest = new URLRequest(
                BASE_URL + encodeURIComponent(videoId) + "/access-rights/hls"
            );
            req.method = "POST";
            req.data = JSON.stringify({"outputs": [[videoStreamId, audioStreamId]]});
            req.requestHeaders = [
                new URLRequestHeader("X-Access-Right-Key", accessRightKey),
                new URLRequestHeader("X-Request-With", "https://www.nicovideo.jp"),
                new URLRequestHeader("Content-Type", "application/json"),
                new URLRequestHeader("Accept", "application/json")
            ];
            this.load(req);
        }
    }
}
