package org.mineap.nicovideo4as.analyzer {
    /**
     * マイリストグループ取得APIの応答を解析するクラスです。
     *
     * @author shiraminekeisuke(MineAP)
     *
     */
    public class MyListGroupAnalyzer {

        public static const MY_LIST_GROUP: String = "mylistgroup";

        public static const OK: String = "ok";

        public static const ERROR: String = "error";

        private var _result: String = null;

        private var _myListIds: Vector.<String> = new Vector.<String>();

        /**
         *
         *
         */
        public function MyListGroupAnalyzer() {
        }

        /**
         * 渡されたマイリスト一覧API(nvapi /v1/users/me/mylists)の実行結果を解析します。
         * レスポンス: {"meta":{"status":200},"data":{"mylists":[{"id":12345,"name":"...",...}]}}
         *
         * @param data
         *
         */
        public function analyzer(data: String): void {
            this._result = ERROR;
            if (data == null) {
                return;
            }

            try {
                var json: Object = JSON.parse(data);
                if (json.meta == null || int(json.meta.status) != 200) {
                    return;
                }
                if (json.data == null || !(json.data.mylists is Array)) {
                    return;
                }
                for each(var mylist: Object in (json.data.mylists as Array)) {
                    if (mylist != null && mylist.id != null) {
                        this._myListIds.push(String(mylist.id));
                    }
                }
                this._result = OK;
            } catch (error: Error) {
                trace(error.getStackTrace());
            }
        }

        /**
         * MyListGroupを解析した結果得られたマイリストIDの一覧
         *
         * @return
         *
         */
        public function get myListIds(): Vector.<String> {
            return this._myListIds;
        }

        /**
         * MyListGroup取得APIへのアクセス結果
         *
         * @return
         *
         */
        public function get result(): String {
            return this._result;
        }

    }
}