# LadyGo

Android-приложение сервиса поездок LadyGo. Этот репозиторий — отдельная рабочая копия исходников для разработки и аудита.

- Android application ID: `com.ladygo.app`
- Expo SDK: 54
- React Native: 0.81.5
- Основной экран: `src/LadyGoApp.js`
- Фирменный цвет: `#E84F87`

## Состояние проекта

Клиентское приложение и найденные SQL-миграции перенесены из исходного репозитория. Это **не подтверждает**, что Supabase backend полностью развёрнут или что все сценарии уже работают в production. Перед использованием нужно закрыть блокеры из [AUDIT_RU.md](./AUDIT_RU.md).

## Запуск локально

Требуется Node.js 22 и npm.

1. Скопируй `.env.example` в локальный `.env`.
2. Заполни URL Supabase и только публичный anon/publishable key.
3. Выполни:

```bash
npm install
npx expo config --type public
npx expo start
```

Для проверки Android bundle:

```bash
npx expo export --platform android
```

## Переменные окружения

- `EXPO_PUBLIC_SUPABASE_URL`
- `EXPO_PUBLIC_SUPABASE_ANON_KEY` — только публичный ключ клиента.
- `EXPO_PUBLIC_GEOAPIFY_API_KEY` — необязательный ключ Geoapify.
- `EXPO_PUBLIC_PROTOMAPS_STYLE_URL` — необязательный URL стиля MapLibre.

Все `EXPO_PUBLIC_*` значения попадают в клиентскую сборку. Не добавляй сюда service-role key, пароли, приватные токены или другие серверные секреты.

## Supabase

- Базовая схема: `schema.sql`.
- Дополнительные изменения: `supabase/migrations/`.
- Edge Function в репозитории: `supabase/functions/send-driver-offer-push/`.

Не запускай миграции вслепую в рабочей базе. Сначала проверь текущие таблицы, функции, RLS, realtime, storage и совместимость миграций с реальной схемой.

## Сборка APK

GitHub Actions → **Android APK Build** → **Run workflow**. Сборка запускается вручную, APK загружается как artifact. CI-проверки выполняются отдельно при push и pull request.

## Безопасность

Репозиторий публичный. Не коммить `.env`, пользовательские данные, service-role key, пароли и приватные токены. Доступ к данным Supabase должен ограничиваться RLS.
