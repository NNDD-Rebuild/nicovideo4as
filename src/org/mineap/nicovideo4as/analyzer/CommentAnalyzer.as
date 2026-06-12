package org.mineap.nicovideo4as.analyzer {

    import org.mineap.nicovideo4as.model.Comment;

    public class CommentAnalyzer {

        private var _click_revision: String = null;

        private var _last_res: Number = 0;

        private var _num_clicks: Number = 0;

        private var _resultcode: int = 0;

        private var _revision: int = 0;

        private var _server_time: Number = 0;

        private var _thread: String = null;

        private var _ticket: String = null;

        private var _comments: Vector.<Comment> = new Vector.<Comment>();


        /**
         *
         *
         */
        public function CommentAnalyzer() {
        }

        /**
         *
         * @param xml
         * @param loadCommentCount
         * @return
         *
         */
        public function analyze(xml: XML, loadCommentCount: Number = 250): Boolean {

            try {

                var thread: XML = xml.thread[0];
                this._click_revision = thread.click_revision;
                this._last_res = Number(thread.last_res);
                this._num_clicks = Number(thread.num_clicks);
                this._resultcode = int(thread.resultcode);
                this._revision = int(thread.revision);
                this._server_time = Number(thread.server_time);
                this._thread = thread.thread;
                this._ticket = thread.ticket;

                var items: XMLList = xml.chat;

                for (var i: int = 0; i < loadCommentCount && i < items.length(); i++) {
                    var p: XML = items[i];
                    _comments[i] = new Comment(Number(p.attribute("vpos")), String(p.text()), String(p.attribute("mail")), String(p.attribute("user_id")), Number(p.attribute("no")), String(p.attribute("thread")), Number(p.attribute("date")));
                }

                return true;

            } catch (error: Error) {
                trace(error.getStackTrace());
            }

            return false;

        }

        public function get comments(): Vector.<Comment> {
            return _comments;
        }


        public function get ticket(): String {
            return _ticket;
        }


        public function get thread(): String {
            return _thread;
        }


        public function get server_time(): Number {
            return _server_time;
        }


        public function get revision(): int {
            return _revision;
        }


        public function get resultcode(): int {
            return _resultcode;
        }

        public function get num_clicks(): Number {
            return _num_clicks;
        }


        public function get last_res(): Number {
            return _last_res;
        }


        public function get click_revision(): String {
            return _click_revision;
        }

        /**
         * nvcomment API の JSON レスポンスを解析する（新仕様）
         * @param json nvcomment /v1/threads レスポンス全体
         * @param loadCommentCount 取得上限数
         */
        public function analyzeJson(json: Object, loadCommentCount: Number = 1000): Boolean {
            try {
                if (json == null || json.data == null) return false;
                var threads: Array = json.data.threads as Array;
                if (threads == null) return false;

                var commentList: Vector.<Comment> = new Vector.<Comment>();
                for each (var thread: Object in threads) {
                    if (thread.comments == null) continue;
                    var comments: Array = thread.comments as Array;
                    for each (var c: Object in comments) {
                        var vpos: Number = Math.round(Number(c.vposMs) / 10);
                        var body: String = c.body ? String(c.body) : "";
                        var mail: String = (c.commands && (c.commands as Array).length > 0)
                            ? (c.commands as Array).join(" ") : "";
                        var userId: String = c.userId ? String(c.userId) : "";
                        var no: Number = Number(c.no || 0);
                        var threadId: String = thread.id ? String(thread.id) : "";
                        var date: Number = 0;
                        if (c.postedAt) {
                            try { date = new Date(String(c.postedAt)).time / 1000; } catch (e: Error) {}
                        }
                        commentList.push(new Comment(vpos, body, mail, userId, no, threadId, date));
                        if (commentList.length >= loadCommentCount) break;
                    }
                    if (commentList.length >= loadCommentCount) break;
                }
                this._comments = commentList;
                return true;
            } catch (e: Error) {
                trace(e.getStackTrace());
            }
            return false;
        }

    }
}