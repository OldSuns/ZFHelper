import 'package:zfhelper/data/storage/appearance_store.dart';
import 'package:zfhelper/ui/features/settings/view_models/appearance_view_model.dart';

AppearanceViewModel testAppearance({AppearanceStore? store}) =>
    AppearanceViewModel(store: store ?? TestAppearanceStore());

final class TestAppearanceStore implements AppearanceStore {
  AppAppearance value = AppAppearance.system;

  @override
  Future<AppAppearance> read() async => value;

  @override
  Future<void> write(AppAppearance appearance) async {
    value = appearance;
  }
}
