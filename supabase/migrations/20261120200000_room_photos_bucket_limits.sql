-- Limita o bucket room-photos a fotos de até 10 MB, só jpeg, png e webp.
-- Achado 2 da varredura de impacto de 20/11/2026 (Securitron).
-- O app Parceiro já envia sempre image/jpeg. O bucket estava vazio quando
-- esta migração foi aplicada, então nenhum arquivo existente fica fora da regra.
update storage.buckets
set
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id = 'room-photos';
