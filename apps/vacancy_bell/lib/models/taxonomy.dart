/// The fixed vocabularies of the feed (SCHEMA.md): post types, categories,
/// qualifications and state codes.
library;

import '../core/json_read.dart';

enum PostType {
  job('job'),
  admitCard('admit_card'),
  result('result'),
  answerKey('answer_key'),
  syllabus('syllabus'),
  admission('admission'),
  notice('notice');

  const PostType(this.wire);
  final String wire;

  /// Unknown or missing types are shown as notices rather than dropped.
  static PostType parse(Object? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return PostType.notice;
  }

  static PostType? tryParse(Object? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

enum JobCategory {
  ssc('ssc'),
  railway('railway'),
  banking('banking'),
  upsc('upsc'),
  defence('defence'),
  police('police'),
  teaching('teaching'),
  statePsc('state_psc'),
  psu('psu'),
  medical('medical'),
  engineering('engineering'),
  other('other');

  const JobCategory(this.wire);
  final String wire;

  static JobCategory parse(Object? v) => tryParse(v) ?? JobCategory.other;

  static JobCategory? tryParse(Object? v) {
    for (final c in values) {
      if (c.wire == v) return c;
    }
    return null;
  }
}

/// A qualification a post asks for. The user's own highest qualification
/// uses the same values except [any].
enum Qualification {
  class8('8th'),
  class10('10th'),
  class12('12th'),
  iti('iti'),
  diploma('diploma'),
  graduate('graduate'),
  engineering('engineering'),
  medical('medical'),
  law('law'),
  postgraduate('postgraduate'),
  any('any');

  const Qualification(this.wire);
  final String wire;

  static Qualification? tryParse(Object? v) {
    final s = v is String ? v.trim().toLowerCase() : null;
    for (final q in values) {
      if (q.wire == s) return q;
    }
    return null;
  }

  /// The choices a user can pick as "highest qualification".
  static const userLevels = [
    class8,
    class10,
    class12,
    iti,
    diploma,
    graduate,
    engineering,
    medical,
    law,
    postgraduate,
  ];
}

class IndianState {
  const IndianState(this.code, this.en, this.hi);
  final String code;
  final String en;
  final String hi;

  String name(AppLang lang) => lang == AppLang.hi ? hi : en;
}

/// Code used in the feed for posts open to candidates from every state.
const allStates = 'all';

/// States and union territories, by the codes in SCHEMA.md.
const indianStates = <IndianState>[
  IndianState('AN', 'Andaman & Nicobar', 'अंडमान और निकोबार'),
  IndianState('AP', 'Andhra Pradesh', 'आंध्र प्रदेश'),
  IndianState('AR', 'Arunachal Pradesh', 'अरुणाचल प्रदेश'),
  IndianState('AS', 'Assam', 'असम'),
  IndianState('BR', 'Bihar', 'बिहार'),
  IndianState('CH', 'Chandigarh', 'चंडीगढ़'),
  IndianState('CG', 'Chhattisgarh', 'छत्तीसगढ़'),
  IndianState('DN', 'Dadra & Nagar Haveli and Daman & Diu',
      'दादरा और नगर हवेली और दमन और दीव'),
  IndianState('DL', 'Delhi', 'दिल्ली'),
  IndianState('GA', 'Goa', 'गोवा'),
  IndianState('GJ', 'Gujarat', 'गुजरात'),
  IndianState('HR', 'Haryana', 'हरियाणा'),
  IndianState('HP', 'Himachal Pradesh', 'हिमाचल प्रदेश'),
  IndianState('JK', 'Jammu & Kashmir', 'जम्मू और कश्मीर'),
  IndianState('JH', 'Jharkhand', 'झारखंड'),
  IndianState('KA', 'Karnataka', 'कर्नाटक'),
  IndianState('KL', 'Kerala', 'केरल'),
  IndianState('LA', 'Ladakh', 'लद्दाख'),
  IndianState('LD', 'Lakshadweep', 'लक्षद्वीप'),
  IndianState('MP', 'Madhya Pradesh', 'मध्य प्रदेश'),
  IndianState('MH', 'Maharashtra', 'महाराष्ट्र'),
  IndianState('MN', 'Manipur', 'मणिपुर'),
  IndianState('ML', 'Meghalaya', 'मेघालय'),
  IndianState('MZ', 'Mizoram', 'मिज़ोरम'),
  IndianState('NL', 'Nagaland', 'नागालैंड'),
  IndianState('OD', 'Odisha', 'ओडिशा'),
  IndianState('PY', 'Puducherry', 'पुडुचेरी'),
  IndianState('PB', 'Punjab', 'पंजाब'),
  IndianState('RJ', 'Rajasthan', 'राजस्थान'),
  IndianState('SK', 'Sikkim', 'सिक्किम'),
  IndianState('TN', 'Tamil Nadu', 'तमिलनाडु'),
  IndianState('TS', 'Telangana', 'तेलंगाना'),
  IndianState('TR', 'Tripura', 'त्रिपुरा'),
  IndianState('UP', 'Uttar Pradesh', 'उत्तर प्रदेश'),
  IndianState('UK', 'Uttarakhand', 'उत्तराखंड'),
  IndianState('WB', 'West Bengal', 'पश्चिम बंगाल'),
];

final Map<String, IndianState> stateByCode = {
  for (final s in indianStates) s.code: s,
};

/// Normalises a state code from the feed ("all", "UP", "up"). Null if unknown.
String? parseStateCode(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  if (s.toLowerCase() == allStates) return allStates;
  final up = s.toUpperCase();
  return stateByCode.containsKey(up) ? up : null;
}
