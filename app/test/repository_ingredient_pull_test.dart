import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/data/repository.dart';

/// Sin `TestWidgetsFlutterBinding`: el binding de flutter_test intercepta
/// `HttpClient` y devuelve 400, así que esta prueba usa un servidor local real.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'el sondeo de ingredientes se reanuda y aplica descuentos posteriores',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var remoteStock = 2560.0;
      var failNextIngredientsGet = false;

      server.listen((request) async {
        final path = request.uri.path;
        await request.drain<void>();
        final response = request.response
          ..headers.contentType = ContentType.json;

        if (path == '/api/ingredients' && request.method == 'GET') {
          if (failNextIngredientsGet) {
            failNextIngredientsGet = false;
            response.statusCode = 500;
          } else {
            response.write(
              jsonEncode({
                'configured': true,
                'ingredients': [
                  {
                    'id': 'carne-res',
                    'name': 'Carne de res',
                    'unit': 'g',
                    'stock': remoteStock,
                    'minStock': 800,
                  },
                ],
              }),
            );
          }
        } else {
          response.write('{}');
        }
        await response.close();
      });

      SharedPreferences.setMockInitialValues({
        'rm_server_url_v1': 'http://127.0.0.1:${server.port}',
        'rm_ingredients_v1': jsonEncode([
          {
            'id': 'carne-res',
            'name': 'Carne de res local',
            'unit': 'g',
            'stock': 9999,
            'minStock': 800,
            'cost': 18,
          },
        ]),
      });

      final repository = await RestaurantRepository.load(
        watchConnectivity: true,
      );
      addTearDown(() async {
        repository.dispose();
        await server.close();
      });

      // El arranque ya consumió el primer pull; esperamos a que aplique.
      for (var attempt = 0; attempt < 100; attempt++) {
        if (repository.ingredientById('carne-res')?.stock == 2560) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(repository.ingredientById('carne-res')!.stock, 2560);

      remoteStock = 2000;
      expect(await repository.pullServerIngredients(), greaterThan(0));
      expect(repository.ingredientById('carne-res')!.stock, 2000);

      // Un fallo de red no debe dejar el guard bloqueado.
      remoteStock = 1500;
      failNextIngredientsGet = true;
      expect(await repository.pullServerIngredients(), 0);
      expect(repository.ingredientById('carne-res')!.stock, 2000);

      expect(await repository.pullServerIngredients(), greaterThan(0));
      expect(repository.ingredientById('carne-res')!.stock, 1500);
    },
  );
}
