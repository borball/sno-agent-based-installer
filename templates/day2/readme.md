Some CRs are not supported during installation, those can/shall be done as day 2 operations.

Operator day2 config can use profile **names** (subfolders under `templates/day2/<operator>/`) or **paths** (file or directory; e.g. `${HOME}/day2/ptp/c`). For paths: a single file is applied as-is; a directory has all supported files applied. Execution order: `*.sh` first, then `*.yaml` and `*.yaml.j2`.
