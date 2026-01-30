# AurAchieve

**Fix your damn life.**

AurAchieve is the only self-improvement app you'll ever need. Earn Aura for every good thing you do. Prove it with AI, a timer, or just your honesty.

Get it now through [GitHub actions](https://github.com/NiceSapien/AurAchieve/actions).

Get into the community for insider news and updates!: [Discord](https://discord.gg/XQ5U7p7bdz)

Pre-register for release: [Google forms](https://docs.google.com/forms/d/e/1FAIpQLSdA6v4FyNCA9lzf_E-mPBP-PtF9ioedzijNrLCMPM9F_WuFgA/viewform?usp=header)

## Self-hosting

If you wish to self-host AurAchieve for some reason, you'll have to clone and deploy the [backend](https://github.com/NiceSapien/AurAchieve-backend) repository, written in ExpressJS. The instructions to setup the backend are present in the repository readme.

To setup the frontend, you can either build the apk with your server URL preset or you can use the official version and set your own URL. To do so, tap on the main intro screen (before signup/login) 7 times and a prompt to enter your server URL will open. Just enter it and you'll be connected to your own server. Alternatively if you'd like to build the APK yourself, follow these steps:

1. Clone the repository
2. Install flutter and download packages

```bash
pub get && flutter pub get
```

3. Edit lib/api_service.dart with your own backend URL.

4. Update lib/main.dart with you own appwrite project. Do **not** use AurAchieve's project ID, or your self hosted version won't work!

5. Build. That's all.

```bash
flutter build apk --profile
```

## Contributing

There's not much about contributing yet. Make sure to deploy your own backend and not use AurAchieve's server URL for testing. After you're done, revert it back to ours and make a pull request. Here's how you may make commits:

`feat`: For new features

`improve`: For improvement of existing features

`fix`: For bug fixes

`delete`: For deleting something

`upgrade`: For upgrading/updating something, such as dependencies

`docs`: Anything related to documentation and not to the codebase itself

`refactor`: When refactoring some part of the codebase.

## Sponsors

- [Renarin Kholin](https://github.com/renarin-kholin), $15

If you appreciate AurAchieve and want to keep it free for everyone, hit the [sponsor](https://github.com/sponsors/NiceSapien) button. You can also do this through [patreon](https://patreon.com/nicesapien), but GitHub sponsors is preferred over Patreon as it charges less. The codebase is provided under the MIT license absolutely free of charge.



Current goals:

Any amount - Show appreciation and help keep AurAchieve free

**100$** - Publish AurAchieve on the Apple App Store

**1000$** - Buy me a MacBook to make iOS development easier, quicker, more efficient and introduce more features to the iOS version!