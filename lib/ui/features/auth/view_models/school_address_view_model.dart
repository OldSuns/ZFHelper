import 'package:flutter/foundation.dart';
import 'package:zf_core/zf_core.dart';

/// Edits an uncommitted school address without changing the active account.
final class SchoolAddressViewModel extends ChangeNotifier {
  SchoolAddressViewModel({this.initialProfile, String? address}) {
    if (address == null) {
      _recognizedAddress = initialProfile?.baseUri;
    } else {
      changeAddress(address);
    }
  }

  final SchoolConnection? initialProfile;
  Uri? _recognizedAddress;
  String? _parseError;
  String? _nameError;
  bool _submitted = false;

  Uri? get recognizedAddress => _recognizedAddress;
  String? get addressError => _submitted ? _parseError : null;
  String? get nameError => _nameError;

  void changeName(String value) {
    if (_nameError == null) return;
    _nameError = null;
    notifyListeners();
  }

  bool get resetsCustomSettings {
    final initialProfile = this.initialProfile;
    if (initialProfile == null) return false;
    if (_recognizedAddress == null ||
        _recognizedAddress == initialProfile.baseUri) {
      return false;
    }
    final defaults = SchoolConnection(
      name: initialProfile.name,
      baseUri: initialProfile.baseUri,
    );
    return initialProfile.loginPath != defaults.loginPath ||
        initialProfile.publicKeyPath != defaults.publicKeyPath ||
        initialProfile.captchaPath != defaults.captchaPath ||
        initialProfile.accountPath != defaults.accountPath ||
        initialProfile.schedulePagePath != defaults.schedulePagePath ||
        initialProfile.scheduleQueryPath != defaults.scheduleQueryPath ||
        initialProfile.schedulePeriodsPath != null ||
        initialProfile.webLoginUri != null;
  }

  void changeAddress(String value) {
    try {
      _recognizedAddress = recognizeSchoolAddress(value);
      _parseError = null;
    } on FormatException catch (error) {
      _recognizedAddress = null;
      _parseError = error.message;
    }
    notifyListeners();
  }

  SchoolConnection? submit(String name) {
    _submitted = true;
    _nameError = name.trim().isEmpty ? '请填写学校名称' : null;
    if (_recognizedAddress == null && _parseError == null) {
      _parseError = '请填写教务系统网址';
    }
    notifyListeners();
    final address = _recognizedAddress;
    if (address == null || _nameError != null) return null;
    final displayName = name.trim();
    final initialProfile = this.initialProfile;
    if (initialProfile == null || address != initialProfile.baseUri) {
      return SchoolConnection(name: displayName, baseUri: address);
    }
    return SchoolConnection(
      name: displayName,
      baseUri: address,
      loginPath: initialProfile.loginPath,
      publicKeyPath: initialProfile.publicKeyPath,
      captchaPath: initialProfile.captchaPath,
      accountPath: initialProfile.accountPath,
      schedulePagePath: initialProfile.schedulePagePath,
      scheduleQueryPath: initialProfile.scheduleQueryPath,
      schedulePeriodsPath: initialProfile.schedulePeriodsPath,
      webLoginUri: initialProfile.webLoginUri,
    );
  }
}
