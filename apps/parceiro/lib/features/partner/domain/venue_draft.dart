/// Campos da casa antes de gravar em `venues`.
class VenueDraft {
  const VenueDraft({
    required this.name,
    required this.cityId,
    required this.neighborhood,
    required this.street,
    required this.number,
    required this.postalCode,
    required this.phone,
    required this.documentKind,
    required this.documentNumber,
    required this.category,
    required this.incomeReais,
    this.inviteCode = '',
  });

  final String name;
  final String cityId;
  final String neighborhood;
  final String street;
  final String number;
  final String postalCode;
  final String phone;
  final String documentKind;
  final String documentNumber;
  final String category;
  final String incomeReais;
  final String inviteCode;

  static String digits(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

  String? validate() {
    final house = name.trim();
    if (house.length < 2 || house.length > 80) {
      return 'O nome da casa fica entre 2 e 80 caracteres.';
    }
    if (cityId.trim().isEmpty) return 'Escolha a cidade.';
    final area = neighborhood.trim();
    if (area.length < 2 || area.length > 80) {
      return 'Informe o bairro.';
    }
    if (street.trim().length < 2) return 'Informe a rua.';
    final cep = digits(postalCode);
    if (cep.length != 8) return 'O CEP tem 8 números.';
    final tel = digits(phone);
    if (tel.length < 10 || tel.length > 13) {
      return 'O telefone tem entre 10 e 13 números.';
    }
    final doc = digits(documentNumber);
    if (documentKind == 'cpf' && doc.length != 11) {
      return 'O CPF tem 11 números.';
    }
    if (documentKind == 'cnpj' && doc.length != 14) {
      return 'O CNPJ tem 14 números.';
    }
    if (documentKind != 'cpf' && documentKind != 'cnpj') {
      return 'Escolha CPF ou CNPJ.';
    }
    if (!categories.containsKey(category)) return 'Escolha a categoria.';
    final income = double.tryParse(incomeReais.trim().replaceAll(',', '.'));
    if (income == null || income <= 0) {
      return 'Informe a renda mensal em reais.';
    }
    final code = inviteCode.trim().toLowerCase();
    if (code.isNotEmpty &&
        !RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(code)) {
      return 'O código do convite usa letras minúsculas e hífen.';
    }
    return null;
  }

  static const categories = <String, String>{
    'escape-room': 'Escape room',
    'rpg': 'RPG',
    'board-game': 'Jogos de tabuleiro',
    'laser-tag': 'Laser tag',
    'immersive': 'Imersivo',
  };
}
