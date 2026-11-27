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
    this.companyType = 'LIMITED',
    this.inviteCode = '',
    this.referralCode = '',
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
  final String companyType;
  final String inviteCode;
  final String referralCode;

  /// Rascunho da unidade da próxima cidade escolhida no mesmo cadastro.
  ///
  /// Repete o que é da casa (nome, telefone, tipo e número do documento,
  /// categoria, faturamento). O endereço é de cada cidade e volta vazio.
  /// Convite e indicação ficam só na primeira unidade.
  /// [keepDocument]: a casa escolheu "mesmo CNPJ em todas as cidades". Com
  /// "CNPJ próprio por cidade", o documento vem vazio para a próxima.
  VenueDraft forNextCity(String nextCityId, {bool keepDocument = true}) {
    return VenueDraft(
      name: name,
      cityId: nextCityId,
      neighborhood: '',
      street: '',
      number: '',
      postalCode: '',
      phone: phone,
      documentKind: documentKind,
      documentNumber: keepDocument ? documentNumber : '',
      category: category,
      incomeReais: incomeReais,
      companyType: companyType,
    );
  }

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
    if (documentKind == 'cnpj' && !companyTypes.containsKey(companyType)) {
      return 'Escolha o tipo da empresa.';
    }
    if (!categories.containsKey(category)) return 'Escolha a categoria.';
    final income = double.tryParse(incomeReais.trim().replaceAll(',', '.'));
    if (income == null || income <= 0) {
      return 'Informe a renda mensal em reais.';
    }
    final referral = referralCode.trim().toUpperCase();
    if (referral.isNotEmpty && !RegExp(r'^[A-Z0-9]{8}$').hasMatch(referral)) {
      return 'O código de indicação tem 8 letras ou números.';
    }
    final code = inviteCode.trim().toLowerCase();
    if (code.isNotEmpty &&
        !RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(code)) {
      return 'O código do convite usa letras minúsculas e hífen.';
    }
    return null;
  }

  /// Tipos aceitos pela API de subcontas do PagBank. LIMITED é o padrão.
  static const companyTypes = <String, String>{
    'MEI': 'MEI',
    'LIMITED': 'Sociedade limitada (LTDA)',
    'INDIVIDUAL': 'Empresário individual',
    'ASSOCIATION': 'Associação',
  };

  static const categories = <String, String>{'escape-room': 'Escape room'};
}
