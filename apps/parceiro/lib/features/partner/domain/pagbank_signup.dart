// Jornada de cadastro PagBank. O modo A não manda estes campos ao servidor.

const pagbankOfficialSignupUrl = 'https://cadastro.pagbank.com.br/';
const pagbankTermsUrl = 'https://pagbank.com.br/regras-de-uso';
const pagbankPrivacyUrl =
    'https://pagseguro.uol.com.br/sobre/politica-de-privacidade';

const pagbankBusinessCategoryLabels = <String, String>{
  'ENTERTAINMENT': 'Serviços de recreação e lazer',
  'ADULT_CONTENT': 'Conteúdo adulto',
  'ARCHITECTURAL_AND_ENGINEERING': 'Arquiteto e engenheiro',
  'ART_AND_ANTIQUE': 'Arte e antiguidades',
  'BABY': 'Bebês',
  'BAKERY': 'Padaria',
  'BEAUTY_AND_BARBER': 'Cabelereiro, barbeiro ou manicure',
  'BED_AND_BATH': 'Cama, mesa e banho',
  'BROKER': 'Corretor de seguro',
  'BUTCHERY': 'Açougue',
  'CANDIES_AND_CONFECTIONERIES': 'Doces e confeitarias',
  'CLOTHING_AND_ACCESSORIES': 'Roupas e acessórios',
  'DENTISTRY': 'Dentista ou ortodontista',
  'DOCTOR': 'Médicos',
  'DOOR_TO_DOOR_SALES': 'Vendas à domicílio',
  'EDUCATION': 'Serviços de educação',
  'FLORIST': 'Jardineiro, florista ou paisagista',
  'FOOD_SERVICE': 'Comida, bebida e nutricional',
  'FREIGHT_FORWARDER': 'Despachante',
  'FURNITURE_AND_DECORATION': 'Móveis e decoração',
  'GENERAL_CONTRACTOR': 'Empreiteiros autônomos',
  'GOVERNMENT': 'Entidades públicas',
  'HEALTH_AND_BEAUTY_SERVICE': 'Esteticista ou massagista',
  'HOUSEHOLD_APPLIANCE': 'Eletrônicos e eletrodomésticos',
  'ITINERANT_SALE': 'Ambulante',
  'JEWELRY_AND_WATCH': 'Joias e relógios',
  'KEY_CHAIN': 'Chaveiro',
  'LEGAL_SERVICE': 'Advogados e serviços legais',
  'LODGING': 'Hospedagem e turismo',
  'MEDICAL_SERVICE': 'Saúde',
  'NONDURABLE_GOODS': 'Feira livre',
  'OTHER_SERVICES': 'Marceneiros, serralheiros ou vidraceiros',
  'PACKAGE_STORE': 'Comércio de bebidas',
  'PERSONAL_TRAINER': 'Personal trainer',
  'PET_SUPPLIES': 'Pet shop',
  'PHOTOGRAPHY_AND_VIDEO': 'Fotografia e gravação',
  'PODIATRIST_AND_CHIROPODIST': 'Podólogos ou pedicuros',
  'PROFESSIONAL_SERVICE': 'Serviços profissionais',
  'REAL_ESTATE_AGENT': 'Corretor de imóveis',
  'RELIGION_AND_SPIRITUALITY': 'Artigos religiosos',
  'REPAIR_SHOPS': 'Reparos diversos',
  'RESTAURANT': 'Restaurantes',
  'SHOE_STORE': 'Sapateiro',
  'SPORT': 'Esporte',
  'SUPERMARKET': 'Mercado',
  'TAILOR_AND_SEAMSTRESS': 'Alfaiates e costureiras',
  'TATTOOIST': 'Tatuadores',
  'TELECOMMUNICATION': 'Celulares e telefonia',
  'TRANSPORTATION_SERVICE': 'Táxi e autônomos',
  'VEHICLE_AND_PARTS': 'Automóveis e acessórios',
  'VEHICLE_SERVICES': 'Borracheiro, mecânico ou funilaria',
  'VETERINARY_SERVICE': 'Veterinários',
};

class PagbankSignupDraft {
  const PagbankSignupDraft({
    required this.documentKind,
    required this.documentNumber,
    required this.companyName,
    required this.postalCode,
    required this.street,
    required this.number,
    required this.complement,
    required this.locality,
    required this.city,
    required this.regionCode,
    required this.responsibleName,
    required this.responsibleCpf,
    required this.birthDate,
    required this.phone,
    required this.email,
    required this.businessCategory,
  });

  final String documentKind;
  final String documentNumber;
  final String companyName;
  final String postalCode;
  final String street;
  final String number;
  final String complement;
  final String locality;
  final String city;
  final String regionCode;
  final String responsibleName;
  final String responsibleCpf;
  final String birthDate;
  final String phone;
  final String email;
  final String businessCategory;

  Map<String, Object?> toCreateJson(String venueId) {
    return {
      'venue_id': venueId,
      'document_kind': documentKind,
      'document_number': documentNumber,
      'responsible_cpf': documentKind == 'cnpj' ? responsibleCpf : '',
      'company_name': companyName,
      'street': street,
      'number': number,
      'complement': complement,
      'locality': locality,
      'city': city,
      'region_code': regionCode,
      'postal_code': postalCode,
      'responsible_name': responsibleName,
      'birth_date': birthDate,
      'phone': phone,
      'email': email,
      'business_category': businessCategory,
      'terms_accepted': true,
    };
  }

  static PagbankSignupDraft? tryParse({
    required String documentKind,
    required String documentNumber,
    required String companyName,
    required String postalCode,
    required String street,
    required String number,
    required String complement,
    required String locality,
    required String city,
    required String regionCode,
    required String responsibleName,
    required String responsibleCpf,
    required String birthDate,
    required String phone,
    required String email,
    required String? businessCategory,
    required bool termsAccepted,
    DateTime? today,
  }) {
    if (issue(
          documentKind: documentKind,
          documentNumber: documentNumber,
          companyName: companyName,
          postalCode: postalCode,
          street: street,
          number: number,
          complement: complement,
          locality: locality,
          city: city,
          regionCode: regionCode,
          responsibleName: responsibleName,
          responsibleCpf: responsibleCpf,
          birthDate: birthDate,
          phone: phone,
          email: email,
          businessCategory: businessCategory,
          termsAccepted: termsAccepted,
          today: today,
        ) !=
        null) {
      return null;
    }
    final kind = documentKind == 'cnpj' ? 'cnpj' : 'cpf';
    return PagbankSignupDraft(
      documentKind: kind,
      documentNumber: digits(documentNumber),
      companyName: collapse(companyName),
      postalCode: digits(postalCode),
      street: collapse(street),
      number: collapse(number),
      complement: collapse(complement),
      locality: collapse(locality),
      city: collapse(city),
      regionCode: regionCode.trim().toUpperCase(),
      responsibleName: collapse(responsibleName),
      responsibleCpf: kind == 'cnpj' ? digits(responsibleCpf) : '',
      birthDate: birthDate.trim(),
      phone: digits(phone),
      email: email.trim().toLowerCase(),
      businessCategory: businessCategory!,
    );
  }

  static String? issue({
    required String documentKind,
    required String documentNumber,
    required String companyName,
    required String postalCode,
    required String street,
    required String number,
    required String complement,
    required String locality,
    required String city,
    required String regionCode,
    required String responsibleName,
    required String responsibleCpf,
    required String birthDate,
    required String phone,
    required String email,
    required String? businessCategory,
    required bool termsAccepted,
    DateTime? today,
  }) {
    return stepIssue(
      step: 2,
      documentKind: documentKind,
      documentNumber: documentNumber,
      companyName: companyName,
      postalCode: postalCode,
      street: street,
      number: number,
      complement: complement,
      locality: locality,
      city: city,
      regionCode: regionCode,
      responsibleName: responsibleName,
      responsibleCpf: responsibleCpf,
      birthDate: birthDate,
      phone: phone,
      email: email,
      businessCategory: businessCategory,
      termsAccepted: termsAccepted,
      today: today,
    );
  }

  /// Passo 0: documento. Passo 1: nome e contato. Passo 2: endereço e termos.
  static String? stepIssue({
    required int step,
    required String documentKind,
    required String documentNumber,
    required String companyName,
    required String postalCode,
    required String street,
    required String number,
    required String complement,
    required String locality,
    required String city,
    required String regionCode,
    required String responsibleName,
    required String responsibleCpf,
    required String birthDate,
    required String phone,
    required String email,
    required String? businessCategory,
    required bool termsAccepted,
    DateTime? today,
  }) {
    final kind = documentKind == 'cnpj' ? 'cnpj' : documentKind;
    if (kind != 'cpf' && kind != 'cnpj') return 'documento';
    final document = digits(documentNumber);
    if (kind == 'cpf' && !cpfOk(document)) return 'documento';
    if (kind == 'cnpj' && !cnpjOk(document)) return 'documento';
    if (kind == 'cnpj' && !cpfOk(digits(responsibleCpf))) {
      return 'cpf_responsavel';
    }
    if (step <= 0) return null;

    final company = collapse(companyName);
    final minName = kind == 'cnpj' ? 3 : 2;
    final maxName = kind == 'cnpj' ? 144 : 80;
    if (company.length < minName || company.length > maxName) return 'razao';
    final person = collapse(responsibleName);
    if (person.length < 2 || person.length > 50) return 'responsavel';
    if (!adultBirth(birthDate.trim(), today ?? DateTime.now().toUtc())) {
      return 'nascimento';
    }
    if (!RegExp(r'^([1-9][0-9])9[0-9]{8}$').hasMatch(digits(phone))) {
      return 'celular';
    }
    final mail = email.trim().toLowerCase();
    if (mail.length > 60 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(mail)) {
      return 'email';
    }
    if (businessCategory == null ||
        !pagbankBusinessCategoryLabels.containsKey(businessCategory)) {
      return 'categoria';
    }
    if (step <= 1) return null;

    final region = regionCode.trim().toUpperCase();
    if (collapse(street).isEmpty ||
        collapse(street).length > 150 ||
        collapse(number).isEmpty ||
        collapse(number).length > 8 ||
        collapse(complement).length > 40 ||
        collapse(locality).isEmpty ||
        collapse(locality).length > 60 ||
        collapse(city).isEmpty ||
        collapse(city).length > 90 ||
        !brazilianRegions.contains(region) ||
        digits(postalCode).length != 8) {
      return 'endereco';
    }
    if (!termsAccepted) return 'termos';
    return null;
  }
}

const brazilianRegions = {
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
};

String digits(String value) => value.replaceAll(RegExp(r'\D'), '');

String collapse(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

bool cpfOk(String value) {
  if (!RegExp(r'^[0-9]{11}$').hasMatch(value)) return false;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(value)) return false;
  int digit(int length, int factor) {
    var sum = 0;
    for (var i = 0; i < length; i++) {
      sum += int.parse(value[i]) * (factor - i);
    }
    final mod = (sum * 10) % 11;
    return mod == 10 ? 0 : mod;
  }

  return digit(9, 10) == int.parse(value[9]) &&
      digit(10, 11) == int.parse(value[10]);
}

bool cnpjOk(String value) {
  if (!RegExp(r'^[0-9]{14}$').hasMatch(value)) return false;
  if (RegExp(r'^(\d)\1{13}$').hasMatch(value)) return false;
  const weights = [
    [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
    [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
  ];
  int calc(List<int> weight) {
    var sum = 0;
    for (var i = 0; i < weight.length; i++) {
      sum += int.parse(value[i]) * weight[i];
    }
    final mod = sum % 11;
    return mod < 2 ? 0 : 11 - mod;
  }

  return calc(weights[0]) == int.parse(value[12]) &&
      calc(weights[1]) == int.parse(value[13]);
}

bool adultBirth(String value, DateTime today) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return false;
  }
  final adult = DateTime.utc(today.year, today.month, today.day);
  final limit = DateTime.utc(adult.year - 18, adult.month, adult.day);
  final oldest = DateTime.utc(adult.year - 120, adult.month, adult.day);
  return !date.isAfter(limit) && !date.isBefore(oldest);
}

class PagbankSignupRow {
  const PagbankSignupRow({
    required this.mode,
    required this.documentKind,
    required this.businessCategory,
    required this.accountStatus,
    this.accountId,
  });

  final String mode;
  final String documentKind;
  final String businessCategory;
  final String accountStatus;
  final String? accountId;

  static PagbankSignupRow? fromJson(Object? value) {
    if (value is! Map) return null;
    final mode = value['mode']?.toString() ?? '';
    final kind = value['document_kind']?.toString() ?? '';
    final category = value['business_category']?.toString() ?? '';
    final status = value['account_status']?.toString() ?? '';
    if (mode.isEmpty || kind.isEmpty) return null;
    final account = value['pagbank_account_id']?.toString();
    return PagbankSignupRow(
      mode: mode,
      documentKind: kind,
      businessCategory: category,
      accountStatus: status,
      accountId: account == null || account.isEmpty ? null : account,
    );
  }
}

class PagbankSignupView {
  const PagbankSignupView({required this.apiEnabled, this.signup});

  final bool apiEnabled;
  final PagbankSignupRow? signup;

  static PagbankSignupView fromJson(Object? value) {
    if (value is! Map) return const PagbankSignupView(apiEnabled: false);
    return PagbankSignupView(
      apiEnabled: value['api_enabled'] == true,
      signup: PagbankSignupRow.fromJson(value['signup']),
    );
  }
}

/// A conta PagBank que o servidor guarda para a casa. Vem sempre do servidor,
/// por qualquer aparelho ou sessão: nada dela fica no aparelho. Documento e
/// conta já chegam mascarados. O PagBank só devolve o id da conta na conexão,
/// então não há titular verificado: a tela mostra o nome e o documento da
/// CASA, cadastrados aqui, e o final da conta.
class PagbankAccountView {
  const PagbankAccountView({
    required this.connected,
    this.houseName = '',
    this.bank = 'PagBank',
    this.accountLast4 = '',
    this.documentKind,
    this.documentMasked,
    this.canDisconnect = true,
  });

  static const none = PagbankAccountView(connected: false);

  final bool connected;
  final String houseName;
  final String bank;
  final String accountLast4;
  final String? documentKind;
  final String? documentMasked;
  final bool canDisconnect;

  String get documentLabel =>
      documentKind == 'cnpj' ? 'CNPJ da casa' : 'CPF da casa';

  static PagbankAccountView fromJson(Object? value) {
    if (value is! Map || value['connected'] != true) return none;
    String? text(Object? raw) {
      final item = raw?.toString().trim() ?? '';
      return item.isEmpty ? null : item;
    }

    return PagbankAccountView(
      connected: true,
      houseName: text(value['house_name']) ?? '',
      bank: text(value['bank']) ?? 'PagBank',
      accountLast4: text(value['account_last4']) ?? '',
      documentKind: text(value['document_kind']),
      documentMasked: text(value['document_masked']),
      canDisconnect: value['can_disconnect'] != false,
    );
  }
}
