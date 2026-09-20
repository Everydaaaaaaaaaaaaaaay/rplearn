import type { DictionaryExampleCatalogRepository } from "./catalog-repository.js";

export function createDictionaryExampleCatalogService(
  repository: Pick<DictionaryExampleCatalogRepository, "find">,
) {
  return { find: (lemma: string) => repository.find(lemma.trim().toLowerCase()) };
}
export type DictionaryExampleCatalogService = ReturnType<
  typeof createDictionaryExampleCatalogService
>;
