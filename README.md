# Backroads4Me Home Assistant Add-ons — ALPHA

> ## ⚠️ ALPHA TESTING REPOSITORY — NOT FOR PRODUCTION USE
>
> This repository publishes **pre-release LibreCoach builds** for targeted testing, such as
> protocol probes that never ship in the beta or stable add-ons. Alpha builds may be unstable,
> contain bugs, or change behavior between updates.
>
> For normal use, install LibreCoach from the
> **[stable repository](https://github.com/Backroads4Me/ha-addons)** instead.

## Before testing

- Create a full Home Assistant backup.
- Uninstall the LibreCoach version you are leaving before installing another one, whether you
  are moving to the alpha, back to stable, or between beta and alpha. Stopping it is not enough:
  every LibreCoach version turns on its own **Start on boot** when it runs, so after the next Home
  Assistant restart all installed versions start together and fight over the same Node-RED
  installation, CAN interface, and Home Assistant entities.
- Your settings carry over. Every fresh install copies the settings saved by the stable add-on,
  or, if you have never run stable, the ones saved by the last beta or alpha build.
- Before uninstalling the alpha, finish any test it was installed for, such as exporting a Hughes
  probe report and pressing **Probe Remove Entities**. Stable and beta cannot remove those entities.
- Read the [LibreCoach changelog](./librecoach/CHANGELOG.md) for the behavior under test.
- Expect to provide the alpha version and relevant logs when reporting a problem.

Every image published by this repository uses the **`-alpha`** suffix, such as
`ghcr.io/backroads4me/amd64-librecoach-alpha`. An alpha build does not replace or upgrade the stable
add-on automatically.

## Install the alpha

Only add this repository if you intend to test a pre-release build:

[![Add repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FBackroads4Me%2Fha-addons-alpha)

You can also add `https://github.com/Backroads4Me/ha-addons-alpha` manually under Home Assistant's
add-on repositories. Install **LibreCoach** from **ALPHA TESTING: LibreCoach**, review its
configuration, and then start it once the version you are leaving is uninstalled.

## Report alpha feedback

Open a [bug report](https://github.com/Backroads4Me/ha-addons-alpha/issues/new?template=bug_report.yml)
or a [feature request](https://github.com/Backroads4Me/ha-addons-alpha/issues/new?template=feature_request.yml).
Include the LibreCoach alpha version, affected hardware, expected behavior, actual behavior, and
the relevant add-on or Node-RED logs.

## LibreCoach

The add-on overview is shared with the stable repository, so its installation
button points to stable. Use the alpha installation link above for testing.

- [Add-on overview](./librecoach/README.md)
- [First-start and configuration notes](./librecoach/DOCS.md)
- [Changelog](./librecoach/CHANGELOG.md)

## Contributing

This repository uses a CLA for the LibreCoach add-on. See
[CONTRIBUTING.md](./librecoach/CONTRIBUTING.md) for details.
