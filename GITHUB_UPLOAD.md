# RDataCraft v0.33: GitHub upload

This is the source-only upload folder. Use the existing RDataCraft repository and
its single main branch in GitHub Desktop; do not create another repository.
Review and commit the updated source, then Push origin.

GitHub Actions builds and tests Intel Mac, Apple Silicon and Windows installers
on their matching runners. After every required job passes, it assembles a draft
v0.33 release with three installer downloads, validation, checksums and
corresponding source/build material. Review that draft under Releases and publish
it when ready. No local Windows packaging is needed. See RELEASE.md.

Mac builds are ad-hoc signed and not notarized; Windows setup is unsigned until
you configure distribution signing credentials. GitHub does not add those.
This preparation does not push source, run Actions or publish a release.
