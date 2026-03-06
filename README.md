# Fresh Mandi - Production Grade Monorepo

This repository contains:
- `app/`: Flutter mobile app (Android + iOS) using Clean Architecture + Riverpod.
- `backend/`: Node.js + Express + PostgreSQL REST API with JWT auth.
- `backend/sql/`: database schema and seed scripts.
- `backend/docs/openapi.yaml`: API docs.
- `postman/FreshMandi.postman_collection.json`: Postman collection.
- `.github/workflows/ci.yml`: CI pipeline.

## Quick Start

### 1) Backend
```bash
cd backend
cp .env.example .env
npm install
npm run migrate
npm run seed
npm run dev
```

### 2) Flutter App
```bash
cd app
flutter pub get
flutter run
```

## Notes
- Figma-perfect spacing/tokens should be completed by importing exact token values from your design system.
- This scaffold already includes architecture, feature modules, business logic hooks, API contracts, and production-oriented docs.
