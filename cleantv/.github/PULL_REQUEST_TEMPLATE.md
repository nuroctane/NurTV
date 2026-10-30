## What this changes

<!-- One line: the TV you are adding, or what the fix does. -->

## How you tested it

<!-- The TV and build, what you ran, what verify.sh printed. -->

## Checklist

- [ ] One device report, or one code or docs change, not both
- [ ] The checks in CONTRIBUTING.md pass (`catalog/validate.py`, the tests, `bash -n`)
- [ ] No IP address, MAC address, serial number, Wi-Fi name or account email anywhere
- [ ] For a device report: `status` is `tested` only if the full pass ran and `verify.sh` exited 0
- [ ] For a list change: the packages came from `pm list packages` on your TV
