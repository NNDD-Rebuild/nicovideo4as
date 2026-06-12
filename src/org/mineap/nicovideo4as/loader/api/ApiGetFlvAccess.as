package org.mineap.nicovideo4as.loader.api {
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLVariables;

    /**
     * ニコニコ動画のAPI(getflv)へのアクセスを担当するクラスです。
     *
     * @author shiraminekeisuke(MineAP)
     *
     */
    public class ApiGetFlvAccess extends URLLoader {

        public static const NICO_API_GET_FLV: String = "http://flapi.nicovideo.jp/api/getflv/";

        private var _url: String = NICO_API_GET_FLV;

        /**
         *
         * @param request
         *
         */
        public function ApiGetFlvAccess(request: URLRequest = null) {
            super(request);
        }

        /**
         * FLVのURLを取得する為のAPIへのアクセスを行う
         * @param videoID 動画ID
         *
         */
        public function getAPIResult(videoID: String): void {
            var variables: URLVariables = new URLVariables();

            //FLVのURLを取得する為にニコニコ動画のAPIにアクセスする
            if (videoID.indexOf("nm") != -1) {
                variables.as3 = "1";
            }

            var getAPIRequest: URLRequest;
            var url: String = url + videoID;

            getAPIRequest = new URLRequest(url);
            getAPIRequest.method = "GET";
            getAPIRequest.data = variables;

            this.load(getAPIRequest);
        }

        public function get url(): String {
            return _url;
        }

        public function set url(value: String): void {
            _url = value;
        }

    }
}