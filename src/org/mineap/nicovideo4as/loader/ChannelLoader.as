package org.mineap.nicovideo4as.loader {
    import flash.net.URLLoader;
    import flash.net.URLRequest;

    /**
     * チャンネルの取得を行うクラスです。
     *
     * @author shiraminekeisuke(MineAP)
     *
     */
    public class ChannelLoader extends URLLoader {

        /** チャンネル動画一覧ページ。NNDD-RE と同じく HTML をスクレイピングする (RSS はスレッドIDしか返さない)。 */
        public static const CHANNEL_PAGE_URL: String = "https://ch.nicovideo.jp/";

        /**
         *
         * @param request
         *
         */
        public function ChannelLoader(request: URLRequest = null) {
            super(request);
        }

        /**
         *
         * @param channelId
         *
         */
        public function getChannel(channelId: String, page: int = 0): void {

            var url: String = CHANNEL_PAGE_URL + encodeURIComponent(channelId) + "/video?sort=f&order=d&page=" +
                              (page > 0 ? page : 1);

            var request: URLRequest = new URLRequest(url);

            this.load(request);

        }


    }
}