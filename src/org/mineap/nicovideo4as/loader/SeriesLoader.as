package org.mineap.nicovideo4as.loader {
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;

    /**
     * シリーズの動画一覧を取得するクラスです。
     * nvapi v2 JSON API を使用します (NNDD-RE と同じ仕様)。
     */
    public class SeriesLoader extends URLLoader {

        public static const SERIES_API_URL: String = "https://nvapi.nicovideo.jp/v2/series/";

        /** 1ページあたりの取得件数 */
        public static const PAGE_SIZE: int = 100;

        public function SeriesLoader(request: URLRequest = null) {
            super(request);
        }

        /**
         * @param seriesId シリーズID
         * @param page 1始まりのページ番号(0以下は1として扱う)
         */
        public function getSeries(seriesId: String, page: int = 0): void {
            var url: String = SERIES_API_URL + encodeURIComponent(seriesId) +
                              "?pageSize=" + PAGE_SIZE +
                              "&page=" + (page > 0 ? page : 1);
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
