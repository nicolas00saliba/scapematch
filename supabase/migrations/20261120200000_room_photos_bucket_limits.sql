-- Limita o bucket room-photos a fotos de até 10 MB, só jpeg, png e webp.
-- Achado 2 da varredura de impacto de 20/11/2026 (Securitron).
-- PROPOSTA, ainda não aplicada em produção. Só entra depois do PR do app
-- Parceiro que reduz a foto (~2048 px, JPEG q85): hoje o photo_picker.dart
-- envia a foto crua com contentType image/jpeg fixo.
update storage.buckets
set
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id = 'room-photos';
