import 'dart:async';
import 'dart:io';

import 'package:design_token_lints/src/cli/cli.dart';

Future<void> main(List<String> arguments) async {
  // Writes to a closed pipe (`design_token_lints … | head`) fail
  // asynchronously, so they are caught in the zone, not around the call.
  const brokenPipeCodes = {32, 109, 232};
  await runZonedGuarded(
    () async {
      exitCode = await runCli(arguments);
    },
    (error, stack) {
      if (error is FileSystemException &&
          brokenPipeCodes.contains(error.osError?.errorCode)) {
        return;
      }
      Error.throwWithStackTrace(error, stack);
    },
  );
}
