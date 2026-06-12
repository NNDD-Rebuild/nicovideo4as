package org.mineap.nicovideo4as.analyzer {
    public class DmsResultAnalyzer {
        private var _contentUrl: String = null;

        public function analyze(data: String): void {
            try {
                var json: Object = JSON.parse(data);
                _contentUrl = json.data.contentUrl;
            } catch (e: Error) {
                _contentUrl = null;
            }
        }

        public function get isValid(): Boolean {
            return _contentUrl != null && _contentUrl.length > 0;
        }

        public function get contentUrl(): String {
            return _contentUrl;
        }

        public function reset(): void {
            _contentUrl = null;
        }
    }
}
