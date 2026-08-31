enum RagStage {
  documentParse(1, '文档解析', 'document-parse-page'),
  chunk(2, '切片', 'chunk-lineage-page'),
  fts(3, 'FTS5', 'fts-lineage-page'),
  embedding(4, 'Embedding', 'embedding-microscope-page'),
  vectorSpace(5, '向量空间', 'vector-space-page'),
  candidates(6, '候选池', 'candidate-pool-page'),
  rank(7, '融合/重排', 'rank-trajectory-page'),
  router(8, '路由决策', 'router-decision-page'),
  evidence(9, '证据与上下文', 'evidence-context-page'),
  generation(10, '生成与引用', 'generation-citation-page');

  const RagStage(this.number, this.title, this.pageKey);

  final int number;
  final String title;
  final String pageKey;
}
