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
    import flash.net.URLRequestMethod;

    /**
     * 動画をマイリストに追加するためのクラスです。
     * nvapi の POST /v1/users/me/mylists/{id}/items?itemId=動画ID を使います(トークン取得は不要)。
     * 旧 www.nicovideo.jp/api/mylist/add は廃止されました。
     *
     * @author shiraminekeisuke
     *
     */
    public class MyListAdder extends EventDispatcher {

        /**
         * マイリストへの追加に成功すると、この文字列をEvent種別に持つEventが発行されます。
         */
        public static const SUCCESS: String = "Success";

        /**
         * マイリストへの追加に失敗すると、この文字列をEvent種別に持つErrorEventが発行されます。
         */
        public static const FAIL: String = "Fail";

        /**
         * マイリストに登録しようとしたが重複していたときに、この文字列をEvent種別に持つEventが発行されます。
         */
        public static const DUP_ERROR: String = "DupError";

        /**
         * 指定された動画が存在しない時、この文字列をEvent種別に持つEventが発行されます。
         */
        public static const NOTEXIST: String = "NotExist";

        /**
         * マイリストへの動画追加API(nvapi)。ボディなしの POST。
         */
        public static const API_MYLIST_ADD_BASE: String = "https://nvapi.nicovideo.jp/v1/users/me/mylists/";

        private var _urlLoader: URLLoader = null;

        private var _httpStatus: int = 0;

        private var _finished: Boolean = false;

        /**
         * コンストラクタ
         *
         */
        public function MyListAdder() {
            this._urlLoader = new URLLoader();
        }

        /**
         * マイリストに動画を追加します。user_session の取り込みが必要です(Login.manualUserSession)。
         *
         * @param mylistId 動画を追加したい自分のマイリストのIDです
         * @param videoId 追加する動画のID(sm12345 など)です
         */
        public function addMyList(mylistId: String, videoId: String): void {

            var urlRequest: URLRequest = new URLRequest(
                API_MYLIST_ADD_BASE + encodeURIComponent(mylistId) + "/items?itemId=" + encodeURIComponent(videoId) +
                "&description="
            );
            urlRequest.method = URLRequestMethod.POST;
            // ボディなしの POST だが、AIR は POST にボディが無いとエラーにするため空のデータを入れる
            urlRequest.data = "";
            urlRequest.contentType = "application/x-www-form-urlencoded";
            urlRequest.requestHeaders = [
                new URLRequestHeader("Origin", "https://www.nicovideo.jp"),
                new URLRequestHeader("Referer", "https://www.nicovideo.jp/"),
                new URLRequestHeader("X-Request-With", "https://www.nicovideo.jp"),
                new URLRequestHeader("X-Frontend-Id", "6"),
                new URLRequestHeader("X-Frontend-Version", "0"),
                new URLRequestHeader("X-Client-Os-Type", "others"),
                new URLRequestHeader("X-Niconico-Language", "ja-jp")
            ];
            // user_session を Cookie で付ける(manageCookies=false になる)
            Login.applySessionTo(urlRequest);

            this._httpStatus = 0;
            this._finished = false;
            this._urlLoader.addEventListener(Event.COMPLETE, completeHandler);
            this._urlLoader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, httpResponseEventHandler);
            this._urlLoader.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
            this._urlLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, errorHandler);
            this._urlLoader.load(urlRequest);

        }

        /**
         * 応答を解釈して結果を通知する。AIR は 4xx でも COMPLETE になることがあるため、COMPLETE / IO_ERROR の両方からここに来る。
         *
         * @param body 応答本文(取得できなければ空文字)
         */
        private function finish(body: String): void {
            if (this._finished) {
                return;
            }
            this._finished = true;

            var errorCode: String = null;
            try {
                var json: Object = JSON.parse(body);
                if (json != null && json.meta != null && json.meta.errorCode != null) {
                    errorCode = String(json.meta.errorCode);
                }
            } catch (error: Error) {
                // 本文が JSON でない場合は errorCode なし
            }

            trace(this._httpStatus + ":" + body);
            if (this._httpStatus >= 200 && this._httpStatus < 300) {
                dispatchEvent(new Event(MyListAdder.SUCCESS, false, false));
            } else if (this._httpStatus == 404 || (errorCode != null && /NOT_FOUND/i.test(errorCode))) {
                dispatchEvent(new Event(MyListAdder.NOTEXIST, false, false));
            } else if (this._httpStatus == 409 || (errorCode != null && /DUPLICAT|EXIST/i.test(errorCode))) {
                dispatchEvent(new Event(MyListAdder.DUP_ERROR, false, false));
            } else {
                dispatchEvent(new ErrorEvent(
                    MyListAdder.FAIL,
                    false,
                    false,
                    "status=" + this._httpStatus + (errorCode != null ? ", errorCode=" + errorCode : "")
                ));
            }

            close();
        }

        /**
         *
         * @param event
         *
         */
        private function completeHandler(event: Event): void {
            finish(String((event.currentTarget as URLLoader).data));
        }

        /**
         *
         * @param event
         *
         */
        private function errorHandler(event: ErrorEvent): void {
            trace(event);
            if (this._httpStatus != 0) {
                // サーバーからの応答(4xx 等)は、本文が取れなくてもステータスで判定する
                var body: String = "";
                try {
                    body = String(this._urlLoader.data);
                } catch (error: Error) {
                }
                finish(body);
                return;
            }
            if (this._finished) {
                return;
            }
            this._finished = true;
            dispatchEvent(new ErrorEvent(MyListAdder.FAIL, false, false, event + ":" + event.text));

            close();
        }

        /**
         *
         * @param event
         *
         */
        private function httpResponseEventHandler(event: HTTPStatusEvent): void {
            this._httpStatus = event.status;
            dispatchEvent(event);
        }

        /**
         *
         *
         */
        public function close(): void {
            try {
                if (this._urlLoader != null) {
                    this._urlLoader.close();
                    this._urlLoader = null;
                }
            } catch (error: Error) {
                trace(error.getStackTrace());
            }
        }

    }
}