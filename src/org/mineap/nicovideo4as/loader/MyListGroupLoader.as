package org.mineap.nicovideo4as.loader {
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.HTTPStatusEvent;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;

    import org.mineap.nicovideo4as.Login;


    /**
     *
     * @author shiraminekeisuke
     *
     */
    public class MyListGroupLoader extends URLLoader {

        /** 自分のマイリスト一覧(nvapi)。旧 www.nicovideo.jp/api/mylistgroup/list は廃止された。 */
        public static const NICO_MYLIST_GROUP_API_URL: String = "https://nvapi.nicovideo.jp/v1/users/me/mylists";

        /**
         *
         * @param request
         *
         */
        public function MyListGroupLoader(request: URLRequest = null) {
            if (request != null) {
                this.load(request);
            }
        }

        /**
         * ログイン中のユーザーについて、マイリストグループ（マイリストのIDの一覧）を取得します。
         *
         */
        public function getMyListGroup(): void {

            var urlRequest: URLRequest = new URLRequest(NICO_MYLIST_GROUP_API_URL);
            urlRequest.requestHeaders = [
                new URLRequestHeader("X-Frontend-Id", "6"),
                new URLRequestHeader("X-Frontend-Version", "0"),
                new URLRequestHeader("X-Niconico-Language", "ja-jp")
            ];
            // user_session でログインしている場合は、その値を Cookie で付ける(manageCookies=false になる)
            Login.applySessionTo(urlRequest);

            this.load(urlRequest);
        }

    }
}