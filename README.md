# AurAchieve

**Fix your damn life.**

AurAchieve is the only self-improvement app you'll ever need. Earn Aura for every good thing you do. Prove it with AI, a timer, or just your honesty.

Get it now through [GitHub actions](https://github.com/NiceSapien/AurAchieve/actions).

Get into the community for insider news and updates!: [Discord](https://discord.gg/XQ5U7p7bdz)

Pre-register for release: [Google forms](https://docs.google.com/forms/d/e/1FAIpQLSdA6v4FyNCA9lzf_E-mPBP-PtF9ioedzijNrLCMPM9F_WuFgA/viewform?usp=header)

## Self-hosting

If you wish to self-host AurAchieve for some reason, you'll have to clone the [backend](https://github.com/NiceSapien/AurAchieve-backend) repository aswell, written in ExpressJS. The instructions to setup the backend are present in the repository readme.

To setup the frontend:

1. Clone the repository
2. Install flutter and download packages

```bash
pub get && flutter pub get
```

3. Edit lib/api_service.dart with your own backend URL. Do **not** use our API link!

4. Update lib/main.dart with you own appwrite project. Do **not** use our project ID!

5. Build. That's all.

```bash
flutter build apk --debug
```

## Contributing

There's not much about contributing yet. Make sure to deploy your own backend and not use our API link for testing. After you're done, revert it back to ours and make a pull request. Here's how you may make commits:

`feat`: For new features

`improve`: For improvement of existing features

`fix`: For bug fixes

`delete`: For deleting something

`upgrade`: For upgrading/updating something, such as dependencies

`docs`: Anything related to documentation and not to the codebase itself

`refactor`: When refactoring some part of the codebase.

## Sponsors

Currently, there are no sponsors.

If you appreciate AurAchieve and want to keep it free for everyone, please [sponsor](https://github.com/sponsors/NiceSapien) me. You can also do this through [patreon](https://patreon.com/nicesapien), but GitHub sponsors is preferred over Patreon as it charges less. The codebase is provided under the MIT license absolutely free of charge, forever.



Current goals:

Any amount - Show appreciation and help keep AurAchieve free

**100$** - Publish AurAchieve on the Apple App Store

**1000$** - Buy me a MacBook to make iOS development easier, quicker, more efficient and introduce more features to the iOS version!