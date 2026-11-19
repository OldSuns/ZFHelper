import 'package:zfhelper/data/storage/update_preferences_store.dart';

final class TestUpdatePreferencesStore implements UpdatePreferencesStore {
  UpdatePreferences value = UpdatePreferences.empty;

  @override
  Future<UpdatePreferences> read() async => value;

  @override
  Future<void> write(UpdatePreferences preferences) async {
    value = preferences;
  }
}
