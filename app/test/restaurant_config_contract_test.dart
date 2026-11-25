import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/models/restaurant_appearance.dart';
import 'package:app/core/models/restaurant_settings.dart';

void main() {
  group('contrato de configuración web', () {
    test('apariencia publica banner, logo y colores propios', () {
      const appearance = RestaurantAppearance(
        slogan: 'Slogan',
        heroTitle: 'Título',
        heroDescription: 'Descripción',
        heroBadge: 'Abierto',
        preset: AppearancePreset.custom,
        customColors: {
          'brand': '#123456',
          'accent': '#abcdef',
          'surface': '#ffffff',
          'ink': '#101010',
          'heroFrom': '#eeeeee',
          'heroTo': '#dddddd',
          'footer': '#202020',
        },
      );

      final json = appearance.toJson();
      final nested = json['appearance'] as Map<String, dynamic>;
      expect(nested['preset'], 'custom');
      expect(nested['bannerUrl'], isNull);
      expect(nested['logoUrl'], isNull);
      expect(nested['customColors'], containsPair('brand', '#123456'));
      expect(nested['socialLinks'], {
        'instagram': isNull,
        'tiktok': isNull,
        'facebook': isNull,
      });
      expect(nested['gpsUrl'], isNull);

      final withAssets = RestaurantAppearance(
          slogan: appearance.slogan,
          heroTitle: appearance.heroTitle,
          heroDescription: appearance.heroDescription,
          heroBadge: appearance.heroBadge,
          preset: appearance.preset,
          bannerUrl: 'https://firebasestorage.app/v0/b/b/o/banner.gif',
          logoUrl: 'https://firebasestorage.app/v0/b/b/o/logo.png',
          customColors: appearance.customColors,
          instagramUrl: 'https://instagram.com/mania',
          tiktokUrl: 'https://tiktok.com/@mania',
          facebookUrl: 'https://facebook.com/mania',
          gpsUrl: 'https://maps.google.com/?q=medellin');
      final restored = RestaurantAppearance.fromJson(withAssets.toJson());
      expect(restored.bannerUrl, withAssets.bannerUrl);
      expect(restored.logoUrl, withAssets.logoUrl);
      expect(restored.customColors, withAssets.customColors);
      expect(restored.instagramUrl, withAssets.instagramUrl);
      expect(restored.tiktokUrl, withAssets.tiktokUrl);
      expect(restored.facebookUrl, withAssets.facebookUrl);
      expect(restored.gpsUrl, withAssets.gpsUrl);
    });

    test('limpia redes y mapa cuando el usuario deja los campos vacíos', () {
      final appearance = RestaurantAppearance.defaults.copyWith(
        instagramUrl: '  ',
        tiktokUrl: ' https://tiktok.com/@mania ',
        gpsUrl: '',
      );
      final nested =
          appearance.toJson()['appearance'] as Map<String, dynamic>;
      expect(nested['socialLinks'], {
        'instagram': isNull,
        'tiktok': 'https://tiktok.com/@mania',
        'facebook': isNull,
      });
      expect(nested['gpsUrl'], isNull);
    });

    test('la eliminación de imágenes envía null a la web', () {
      final base = RestaurantAppearance.defaults.copyWith(
        bannerUrl: 'https://firebasestorage.app/v0/b/b/o/banner.gif',
        logoUrl: 'https://firebasestorage.app/v0/b/b/o/logo.png',
      );
      final cleared = base.copyWith(clearBanner: true, clearLogo: true);
      final appearance = cleared.toJson()['appearance'] as Map<String, dynamic>;
      expect(appearance['bannerUrl'], isNull);
      expect(appearance['logoUrl'], isNull);
    });

    test('configuración publica contacto, entrega y pagos', () {
      const settings = RestaurantSettings(
        name: 'Casa Nueva',
        isOpen: true,
        hours: '10:00 - 20:00',
        whatsapp: '+573001234567',
        address: 'Calle 1',
        city: 'Bogotá',
        countryCode: '+57',
        phone: '310 555 0101',
        currency: 'USD',
        showOrderTypeOptions: false,
        deliveryOptions: {'pickup': false, 'delivery': true, 'table': false},
        paymentMethods: ['nequi'],
        paymentMethodLabels: {'nequi': 'Nequi'},
        aiDescription: 'Comida colombiana en Medellín',
        aiKeywords: 'bandeja paisa, ajiaco',
        aiServiceArea: 'Medellín y Ángel',
        aiHighlights: 'Pedidos rápidos',
      );

      final patch = settings.toWebConfigPatch();
      expect(patch['whatsapp'], '+573105550101');
      expect(patch['countryCode'], '+57');
      expect(patch['phone'], '310 555 0101');
      expect(patch['city'], 'Bogotá');
      expect(patch['currency'], 'USD');
      expect(patch['showOrderTypeOptions'], isFalse);
      expect(patch['deliveryOptions'], settings.deliveryOptions);
      expect(patch['paymentMethods'], ['nequi']);
      expect(patch['aiSearch'], {
        'description': 'Comida colombiana en Medellín',
        'keywords': 'bandeja paisa, ajiaco',
        'serviceArea': 'Medellín y Ángel',
        'highlights': 'Pedidos rápidos',
      });
    });

    test('reconcilia la configuración remota sin perder isOpen local', () {
      final current = RestaurantSettings.defaults.copyWith(
        isOpen: false,
        city: 'Medellín',
      );
      final remote = RestaurantSettings.fromWebConfig({
        'name': 'Casa Nueva',
        'city': 'Cali',
        'currency': 'COP',
        'countryCode': '+1',
        'phone': '305 000 0000',
        'showOrderTypeOptions': false,
        'deliveryOptions': {'pickup': true, 'delivery': false, 'table': true},
        'paymentMethods': ['card'],
        'paymentMethodLabels': {'card': 'Tarjeta'},
        'aiSearch': {
          'description': 'Restaurante familiar',
          'keywords': 'comida típica',
          'serviceArea': null,
          'highlights': null,
        },
      }, current);

      expect(remote.isOpen, isFalse);
      expect(remote.city, 'Cali');
      expect(remote.countryCode, '+1');
      expect(remote.phone, '305 000 0000');
      expect(remote.showOrderTypeOptions, isFalse);
      expect(remote.deliveryOptions['delivery'], isFalse);
      expect(remote.paymentMethods, ['card']);
      expect(remote.paymentLabel('card'), 'Tarjeta');
      expect(remote.aiDescription, 'Restaurante familiar');
      expect(remote.aiKeywords, 'comida típica');
      expect(remote.aiServiceArea, current.aiServiceArea);
      expect(remote.aiHighlights, current.aiHighlights);
    });

    test('separa el indicativo de teléfonos guardados con +', () {
      final split = RestaurantSettings.splitPhone('+57 300 123 4567', '');
      expect(split['countryCode'], '+57');
      expect(split['phone'], '300 123 4567');
      expect(
        RestaurantSettings.compactNumber('+57', '300 123 4567'),
        '+573001234567',
      );
    });
  });
}
