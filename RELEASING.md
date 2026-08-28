# Release Process

Releases use Semantic Versioning and immutable Git tags. A release is complete
only when the tagged source, embedded installer version, checksum manifest, and
release archive describe the same content.

## Prepare

1. Choose the next version according to compatibility:
   - Patch: corrections that do not change installation or normative behavior.
   - Minor: backward-compatible guidelines, detection, or installer features.
   - Major: incompatible installer behavior or materially changed normative
     defaults.
2. Update `VERSION` and `INSTALLER_VERSION` in `install.sh` to the same version.
3. Move relevant entries from `Unreleased` into a dated version section in
   `CHANGELOG.md` and update comparison links.
4. Regenerate the payload manifest:

   ```bash
   ./scripts/generate-checksums.sh
   ```

5. Run the complete local release gate:

   ```bash
   bash -n install.sh tests/install.sh scripts/*.sh
   ./scripts/generate-checksums.sh --check
   python3 scripts/validate-guidelines.py
   ./tests/install.sh
   ```

6. Review the diff, especially downloaded payload paths and checksum changes.

## Publish

Publishing changes shared Git state and requires explicit authorization.

1. Commit the prepared release.
2. Create an annotated tag matching `v$(cat VERSION)`.
3. Push the commit and tag.
4. The release workflow validates the tag, rebuilds the source archive, writes
   an archive checksum, and creates the GitHub release.
5. Test the documented installer with the immutable tag before recommending it
   as a pinned production installation.

Never move or reuse a published version tag. Release corrections require a new
version.
