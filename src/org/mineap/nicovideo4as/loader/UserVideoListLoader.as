package org.mineap.nicovideo4as.loader {
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;

    /**
     * ユーザの投稿した動画の一覧を取得するクラスです。
     *
     * @author shiraminekeisuke(MineAP)
     *
     */
    public class UserVideoListLoader extends URLLoader {

        /** ユーザー投稿動画一覧(nvapi)。旧 www.nicovideo.jp/user/{id}/video?rss=2.0 は RSS を返さなくなった。 */
        public static const USER_VIDEO_LIST_URL_PRE: String = "https://nvapi.nicovideo.jp/v3/users/";

        public static const USER_VIDEO_LIST_URL_SUF: String = "/videos";

        public static const PAGE_SIZE: int = 100;

        /**
         *
         * @param request
         *
         */
        public function UserVideoListLoader(request: URLRequest = null) {
            super(request);
        }

        /**
         *
         * @param userId
         * @param page 1始まりのページ番号(0以下は1として扱う)
         *
         */
        public function getVideoList(userId: String, page: int = 0): void {
            var url: String = USER_VIDEO_LIST_URL_PRE + encodeURIComponent(userId) + USER_VIDEO_LIST_URL_SUF +
                              "?sortKey=registeredAt&sortOrder=desc&pageSize=" + PAGE_SIZE +
                              "&page=" + (page > 0 ? page : 1) +
                              "&sensitiveContents=mask";
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