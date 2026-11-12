# Platform permission checklist

| Capability | Android | iOS | When requested |
|---|---|---|---|
| QR scanning camera | `CAMERA` | `NSCameraUsageDescription` | Only when the user opens Scan QR |
| Location for SOS | `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` | `NSLocationWhenInUseUsageDescription` | After the user confirms SOS |
| Push notifications | `POST_NOTIFICATIONS` (Android 13+) | APNs capability + user authorization | Notification onboarding / app startup |
| Microphone | Not requested | Not requested | Not part of MVP |
| Direct SMS | Not requested | Not available as silent send | Server-side Twilio only |
| Background location | Not requested | Not requested | Not part of MVP |

Do not silently record media or use background camera/microphone permissions. The camera in this project is used only for the foreground QR scanner.
