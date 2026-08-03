# Подешавање Google Calendar интеграције (једном, ~15 минута)

Ово мораш да урадиш ти (тражи пријаву на твој Google налог). Након тога ми
дај **Client ID** и **Client secret**, или их сам упиши у `backend/.env`.

## 1. Направи Google Cloud пројекат
1. Отвори https://console.cloud.google.com/
2. Горе лево, падајући мени пројеката → **New Project** → име нпр. `deljeni-kalendar` → **Create**.
3. Сачекај да се направи и изабери тај пројекат.

## 2. Укључи Google Calendar API
1. Мени (☰) → **APIs & Services → Library**.
2. Претражи **Google Calendar API** → отвори → **Enable**.

## 3. Подеси OAuth consent екран
1. **APIs & Services → OAuth consent screen**.
2. User type: **External** → **Create**.
3. Попуни обавезна поља (App name нпр. „Дељени календар“, твој мејл као support/developer) → сачувај и настави кроз кораке.
4. **Scopes** — можеш прескочити (додаћемо у коду), или додати ручно:
   - `https://www.googleapis.com/auth/calendar.readonly`
   - `https://www.googleapis.com/auth/calendar.events`
5. **Test users** → **Add users** → додај свој Google мејл (и сваки налог који ћеш
   користити у демоу, нпр. налог за „Bob“). У „Testing“ режиму само ти налози могу да се пријаве — то нам је сасвим довољно.
6. Сачувај. (Не мораш да тражиш верификацију нити да објављујеш апликацију.)

## 4. Направи OAuth credentials
1. **APIs & Services → Credentials → Create Credentials → OAuth client ID**.
   - Ако те чаробњак прво пита **„What data will you be accessing?“**, изабери
     **User data** (то прави OAuth client; „Application data“ прави service
     account који нам НЕ треба), па прођи кроз App information и Scopes.
2. Application type: **Web application**.
3. Name: нпр. `deljeni-kalendar-web`.
4. **Authorized redirect URIs → Add URI**, унеси тачно:
   ```
   http://localhost:8000/integrations/google/callback
   ```
5. **Create**. Појавиће се **Client ID** и **Client secret** — сачувај их.

## 5. Упиши их у бекенд
У `backend/.env` додај (или ми пошаљи па ћу ја):
```
GOOGLE_CLIENT_ID=<твој client id>
GOOGLE_CLIENT_SECRET=<твој client secret>
GOOGLE_REDIRECT_URI=http://localhost:8000/integrations/google/callback
```

## Како ће се користити (демо)
- Покренеш бекенд, отвориш у прегледачу на рачунару:
  `http://localhost:8000/integrations/google/connect?as=<user_id>` (даћу тачан начин).
- Google те пита за дозволу → вратиш се на бекенд који сачува токене.
- Апликација (на емулатору) онда користи „Предложи термин“ који гледа и Google заузећа.

> Напомена: пошто су токени на серверу, повезивање урадиш једном у прегледачу
> рачунара; апликација дели исти бекенд па одмах има корист.
