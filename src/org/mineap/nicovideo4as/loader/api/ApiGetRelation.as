package org.mineap.nicovideo4as.loader.api {
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;

    /**
     *
     * @author shiraminekeisuke
     *
     */
    public class ApiGetRelation extends URLLoader {

        /** 関連動画(レコメンド)API。旧 ext.nicovideo.jp/api/getrelation は廃止された。 */
        public static const NICO_API_RECOMMEND: String = "https://nvapi.nicovideo.jp/v1/recommend";

        /**
         *
         * @param request
         *
         */
        public function ApiGetRelation(request: URLRequest = null) {
            super(request);
        }

        /**
         * 指定された動画IDに対するオススメ動画情報を取得します。
         * 新APIには並び替え・ページ指定が無いため、page / sort / order は使われません(呼び出し側の互換のために残しています)。
         * @param videoId 動画ID
         * @param page 使われません
         * @param sort 使われません
         * @param order 使われません
         *
         */
        public function getRelation(videoId: String, page: int = 1, sort: String = "p", order: String = "d"): void {
            var url: String = NICO_API_RECOMMEND + "?recipeId=video_watch_recommendation&videoId=" +
                              encodeURIComponent(videoId) + "&site=nicovideo&_frontendId=6&_frontendVersion=0";
            var request: URLRequest = new URLRequest(url);
            request.requestHeaders = [
                new URLRequestHeader("X-Frontend-Id", "6"),
                new URLRequestHeader("X-Frontend-Version", "0"),
                new URLRequestHeader("X-Niconico-Language", "ja-jp")
            ];
            this.load(request);
        }
    }
}