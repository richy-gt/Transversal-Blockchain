# Acuerdo de exportación con pago en garantía (EFT BCY0010)

DApp para exportación de vino chileno: pago en garantía (escrow) con token ERC-20, trazabilidad de cadena de frío vía oráculo y resolución de disputas por una mini-DAO de 3 árbitros.

**Integrantes:** Ricardo Saez · Javier González · Sección 002D · Fundamentos de Blockchain (BCY0010)

## Estructura
- `contracts/AcuerdoExportacion.sol`: `PagoToken` (ERC-20 demo) y `AcuerdoExportacion` (participantes, términos, funciones, estado y firma digital).
- `docs/index.html`: interfaz web (ethers.js + MetaMask). Se publica con GitHub Pages.
- `test/`: pruebas automáticas del contrato (6 escenarios) y de la interfaz.
- `evidencia_pruebas.txt`: salida de las pruebas del contrato.

## Despliegue en Sepolia (Remix)
1. Abre https://remix.ethereum.org, pega `contracts/AcuerdoExportacion.sol`, compila con Solidity 0.8.20 o superior.
2. En MetaMask (red Sepolia, con ETH de prueba) despliega `PagoToken`.
3. Despliega `AcuerdoExportacion` con: dirección del token, exportador, importador, transportista, oráculo, `[árbitro1, árbitro2, árbitro3]`, `"Vino Carmenere Reserva 2023"`, `500`, `12500000000`, `80`, y un timestamp UNIX futuro. Las 8 direcciones deben ser cuentas distintas (usa varias cuentas de MetaMask).
4. Abre la interfaz con `?acuerdo=<dirección>` (o pégala en el campo) y conecta cada cuenta para firmar, depositar, etc.
5. El dueño del token usa «Emitir USDm» para entregar fondos al importador antes de depositar.

## Publicar la interfaz (GitHub Pages)
Settings → Pages → Source: `Deploy from a branch` → Branch `main`, carpeta `/docs`.

## Pruebas locales
```
npm install
npm test        # compila y ejecuta 6 escenarios del contrato
npm run ui      # prueba la interfaz con un navegador automatizado (requiere Chromium de Playwright)
```
