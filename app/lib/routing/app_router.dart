import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/navigation/app_route_observer.dart';
import '../shared/models/models.dart';
import '../features/address/presentation/address_screen.dart';
import '../features/address/presentation/address_form_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/otp_screen.dart';
import '../features/cart/presentation/cart_screen.dart';
import '../features/catalog/presentation/category_list_screen.dart';
import '../features/catalog/presentation/product_details_screen.dart';
import '../features/catalog/presentation/product_list_screen.dart';
import '../features/checkout/presentation/checkout_screen.dart';
import '../features/checkout/presentation/slot_selector_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/orders/presentation/order_confirmation_screen.dart';
import '../features/orders/presentation/order_details_screen.dart';
import '../features/orders/presentation/orders_history_screen.dart';
import '../features/privacy/presentation/privacy_policy_screen.dart';
import '../features/profile/presentation/edit_phone_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/splash/onboarding/presentation/onboarding_screen.dart';
import '../features/splash/onboarding/presentation/splash_screen.dart';
import '../features/terms/presentation/terms_screen.dart';
import '../features/wallet/presentation/wallet_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    observers: [appRouteObserver],
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/otp', builder: (c, s) => OtpScreen(phone: s.uri.queryParameters['phone'] ?? '')),
      GoRoute(
        path: '/address',
        builder: (c, s) => AddressScreen(
          onboardingFlow: s.uri.queryParameters['onboarding'] == '1',
        ),
      ),
      GoRoute(
        path: '/address/form',
        builder: (c, s) => AddressFormScreen(
          addressId: int.tryParse(s.uri.queryParameters['id'] ?? ''),
        ),
      ),
      GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
      GoRoute(path: '/categories', builder: (c, s) => const CategoryListScreen()),
      GoRoute(
        path: '/products',
        builder: (c, s) => ProductListScreen(type: s.uri.queryParameters['type'] ?? 'all'),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (c, s) {
          final id = s.pathParameters['id'] ?? '0';
          final q = s.uri.queryParameters;
          return ProductDetailsScreen(
            product: Product(
              id: id,
              name: q['name'] ?? 'Product',
              price: double.tryParse(q['price'] ?? '') ?? 0,
              unit: q['unit'] ?? 'unit',
              categoryId: q['categoryId'] ?? '',
              imageUrl: q['image']?.isEmpty == true ? null : q['image'],
            ),
          );
        },
      ),
      GoRoute(path: '/cart', builder: (c, s) => const CartScreen()),
      GoRoute(path: '/slots', builder: (c, s) => const SlotSelectorScreen()),
      GoRoute(path: '/checkout', builder: (c, s) => const CheckoutScreen()),
      GoRoute(
        path: '/order-confirmation',
        builder: (c, s) => OrderConfirmationScreen(
          orderId: int.tryParse(s.uri.queryParameters['orderId'] ?? ''),
          total: double.tryParse(s.uri.queryParameters['total'] ?? ''),
          slotLabel: s.uri.queryParameters['slot'],
        ),
      ),
      GoRoute(path: '/orders', builder: (c, s) => const OrdersHistoryScreen()),
      GoRoute(
        path: '/order-details/:id',
        builder: (c, s) => OrderDetailsScreen(orderId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0),
      ),
      GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
      GoRoute(path: '/edit-phone', builder: (c, s) => const EditPhoneScreen()),
      GoRoute(path: '/terms', builder: (c, s) => const TermsScreen()),
      GoRoute(path: '/privacy', builder: (c, s) => const PrivacyPolicyScreen()),
      GoRoute(path: '/notifications', builder: (c, s) => const NotificationsScreen()),
      GoRoute(path: '/wallet', builder: (c, s) => const WalletScreen()),
    ],
  );
});

class FeatureTile extends StatelessWidget {
  const FeatureTile({super.key, required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
