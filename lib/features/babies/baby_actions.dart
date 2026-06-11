import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// "Bebeğim doğdu" → doğum onay/geçiş ekranını açar (design ScrBornFlow).
/// Ekran doğum tarihi + prematürite onayı alır, bebeği 'born'a çevirip /home'a gider.
void openBornFlow(BuildContext context) => context.push('/born-flow');
