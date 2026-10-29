package org.mineap.nicovideo4as.analyzer {
    import org.mineap.nicovideo4as.model.RelationResultItem;

    public class GetRelationResultAnalyzer {

        /**
         * 応答のステータス
         */
        public var status: String = null;

        /**
         * 検索されたオススメ動画の総数
         */
        public var total_count: int = 0;

        /**
         * ページ分けした結果、できたページの数
         */
        public var page_count: int = 0;

        /**
         * レスポンスに含まれる動画データの個数
         */
        public var data_count: int = 0;

        /**
         * レスポンスに含まれる動画情報の一覧
         */
        public var videos: Vector.<RelationResultItem> = new Vector.<RelationResultItem>();

        public function GetRelationResultAnalyzer() {
        }

        /**
         *
         * @param result
         * @return
         *
         */
        public function analyze(result: Object): Boolean {
            try {
                // 新API(nvapi /v1/recommend)のレスポンス: {"meta":{"status":200},"data":{"items":[{"contentType":"video","content":{...}}]}}
                var json: Object = JSON.parse(String(result));
                var metaStatus: int = json.meta != null ? int(json.meta.status) : 0;
                if (metaStatus != 200) {
                    this.status = String(metaStatus);
                    return false;
                }
                this.status = "ok";

                var items: Array = (json.data != null && json.data.items is Array) ? (json.data.items as Array) : [];
                for each(var entry: Object in items) {
                    if (entry == null || entry.contentType != "video" || entry.content == null) {
                        continue;
                    }
                    var c: Object = entry.content;
                    var count: Object = c.count != null ? c.count : {};
                    var thumb: Object = c.thumbnail != null ? c.thumbnail : {};
                    var thumbUrl: String = thumb.listingUrl != null ? String(thumb.listingUrl) :
                                           (thumb.url != null ? String(thumb.url) : "");
                    var item: RelationResultItem = new RelationResultItem(
                        "https://www.nicovideo.jp/watch/" + String(c.id),
                        thumbUrl,
                        c.title != null ? String(c.title) : "",
                        int(count.view),
                        int(count.comment),
                        int(count.mylist),
                        int(c.duration),
                        parseIsoDateToUnixTime(c.registeredAt)
                    );
                    videos.push(item);
                }
                this.data_count = videos.length;
                this.total_count = videos.length;
                this.page_count = 1;
                return true;
            } catch (error: Error) {
                trace(error.getStackTrace());
            }
            return false;
        }

        /**
         * "2026-04-24T20:09:06+09:00" 形式の日時を UNIX 時間(秒)に変換する。変換できなければ 0。
         */
        private function parseIsoDateToUnixTime(value: Object): Number {
            if (value == null) {
                return 0;
            }
            var m: Array = String(value).match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$/);
            if (m == null) {
                return 0;
            }
            var ms: Number = Date.UTC(int(m[1]), int(m[2]) - 1, int(m[3]), int(m[4]), int(m[5]), int(m[6]));
            if (m[7] != "Z") {
                var sign: int = String(m[7]).charAt(0) == "-" ? -1 : 1;
                var offsetMin: int = int(String(m[7]).substr(1, 2)) * 60 + int(String(m[7]).substr(4, 2));
                ms -= sign * offsetMin * 60 * 1000;
            }
            return ms / 1000;
        }
    }
}