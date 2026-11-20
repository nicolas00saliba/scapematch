-- Limita o bucket room-photos a fotos de até 10 MB, só jpeg, png e webp.
-- Achado 2 da varredura de impacto de 20/11/2026 (Securitron).
-- Aplicada em produção em 20/11/2026 (versão 20261120195327), com OK do Nícolas.
-- O bucket estava vazio, então nenhum arquivo existente ficou fora da regra.
-- Atenção: o photo_picker.dart do app Parceiro envia a foto crua com
-- contentType image/jpeg fixo; foto acima de 10 MB passa a ser recusada até
-- o app reduzir a imagem antes do envio.
update storage.buckets
set
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id = 'room-photos';
