/// Links externos de mapa. O app inteiro abre por [openExternalUrl].
Uri googleMapsUri(String query) {
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
}

Uri wazeUri(String query) {
  return Uri.https('waze.com', '/ul', {'q': query, 'navigate': 'yes'});
}
