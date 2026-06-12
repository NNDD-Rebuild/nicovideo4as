package org.mineap.nicovideo4as.loader {
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;

    /**
     * 公開マイリストの取得を行うクラスです。
     * nvapi v2 JSON API を使用します。
     *
     * @author shiraminekeisuke(MineAP)
     *
     */
    public class PublicMyListLoader extends URLLoader {

        // nvapi v1 (自分のマイリスト、ログイン必須)
        public static const MYLIST_API_URL: String = "https://nvapi.nicovideo.jp/v1/users/me/mylists/";
        // nvapi v2 (公開マイリスト、ログイン不要)
        public static const MYLIST_API_URL_V2: String = "https://nvapi.nicovideo.jp/v2/mylists/";
        // RSS フォールバック (WinINetのCookieで非公開マイリストにアクセス)
        public static const MYLIST_RSS_URL: String = "https://www.nicovideo.jp/mylist/";
        public static const PAGE_SIZE: int = 100;

        /**
         *
         * @param request
         *
         */
        public function PublicMyListLoader(request: URLRequest = null) {
            if (request != null) {
                this.load(request);
            }
        }

        /**
         * 指定されたマイリストIDのマイリスト情報を取得します。
         *
         * @param myListId マイリストID
         * @param page 1始まりのページ番号 (デフォルト1)
         */
        public function getMyList(myListId: String, page: int = 1, userSession: String = null): void {
            var url: String = MYLIST_API_URL + myListId + "?pageSize=" + PAGE_SIZE + "&page=" + page;
            var request: URLRequest = new URLRequest(url);
            request.requestHeaders = buildHeaders(userSession);
            this.load(request);
        }

        public function getMyListV2(myListId: String, page: int = 1, userSession: String = null): void {
            var url: String = MYLIST_API_URL_V2 + myListId + "?pageSize=" + PAGE_SIZE + "&page=" + page;
            var request: URLRequest = new URLRequest(url);
            request.requestHeaders = buildHeaders(userSession);
            this.load(request);
        }

        public function getMyListRss(myListId: String, page: int = 1, userSession: String = null): void {
            var url: String = MYLIST_RSS_URL + myListId + "?rss=2.0";
            if (page > 1) url += "&page=" + page;
            var request: URLRequest = new URLRequest(url);
            if (userSession != null) {
                request.requestHeaders = [new URLRequestHeader("Cookie", "user_session=" + userSession)];
            }
            this.load(request);
        }

        private function buildHeaders(userSession: String = null): Array {
            var headers: Array = [
                new URLRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"),
                new URLRequestHeader("Referer", "https://www.nicovideo.jp/"),
                new URLRequestHeader("X-Frontend-Id", "6"),
                new URLRequestHeader("X-Frontend-Version", "0"),
                new URLRequestHeader("X-Client-Os-Type", "others"),
                new URLRequestHeader("X-Niconico-Language", "ja-jp")
            ];
            if (userSession != null) {
                headers.push(new URLRequestHeader("Cookie", "user_session=" + userSession));
            }
            return headers;
        }

    }
}