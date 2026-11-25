// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * EFT BCY0010 - Fundamentos de Blockchain
 * Caso: trazabilidad y pago en garantia (escrow) para exportacion de vino chileno con cadena de frio.
 *
 * Componentes de la DApp:
 *  - PagoToken:          token ERC-20 de demostracion (stablecoin simulada, 6 decimales).
 *  - AcuerdoExportacion: smart contract con participantes, terminos, funciones, estado y firma digital.
 *
 * Roles (participantes): exportador, importador, transportista, oraculo (IoT) y 3 arbitros (mini-DAO).
 */

// ---------------------------------------------------------------------------
// 1) TOKEN DE PAGO (rol de los tokens en la DApp)
// ---------------------------------------------------------------------------
contract PagoToken {
    string public constant name = "Dolar Digital Demo";
    string public constant symbol = "USDm";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    address public immutable owner;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        owner = msg.sender;
    }

    /// @notice Emision solo para demostracion en testnet (equivale a un "faucet").
    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Solo el owner emite");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 permitido = allowance[from][msg.sender];
        require(permitido >= amount, "Allowance insuficiente");
        allowance[from][msg.sender] = permitido - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "Destino invalido");
        require(balanceOf[from] >= amount, "Saldo insuficiente");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

// ---------------------------------------------------------------------------
// 2) SMART CONTRACT DEL ACUERDO
// ---------------------------------------------------------------------------
contract AcuerdoExportacion {
    // ---------------- ESTADO (datos actuales) ----------------
    enum Estado {
        Creado,        // desplegado, esperando firmas
        Firmado,       // ambas partes firmaron los terminos
        Financiado,    // importador deposito el pago en garantia
        EnTransito,    // transportista retiro la carga
        Entregado,     // carga entregada en destino
        Pagado,        // pago liberado al exportador
        EnDisputa,     // DAO de arbitros decide
        Reembolsado,   // pago devuelto al importador
        Cancelado      // cancelado antes de financiar
    }

    Estado public estado;

    // ---------------- PARTICIPANTES ----------------
    address public immutable exportador;
    address public immutable importador;
    address public immutable transportista;
    address public immutable oraculo;      // dispositivo IoT / servicio externo autorizado
    address[3] public arbitros;            // mini-DAO
    PagoToken public immutable token;

    // ---------------- TERMINOS Y CONDICIONES (logica del acuerdo) ----------------
    string public producto;
    uint32 public cantidadCajas;
    uint256 public precio;                 // en unidades minimas del token (6 decimales)
    int16 public temperaturaMaxDecimas;    // 80 = 8,0 grados C
    uint64 public fechaLimiteEntrega;      // timestamp UNIX
    uint64 public constant PLAZO_CONFIRMACION = 3 days;
    bytes32 public immutable hashTerminos; // huella digital (keccak256) de los terminos

    // ---------------- FIRMAS DIGITALES ----------------
    mapping(address => bool) public firmo;
    mapping(address => uint64) public fechaFirma;

    // ---------------- TRAZABILIDAD ----------------
    int16 public ultimaTemperaturaDecimas;
    int16 public maximaTemperaturaDecimas;
    uint32 public totalLecturas;
    bool public incumplimientoTermico;
    uint64 public fechaEntrega;

    // ---------------- DAO DE ARBITROS ----------------
    mapping(address => bool) public esArbitro;
    mapping(address => bool) public yaVoto;
    uint8 public votosImportador;
    uint8 public votosExportador;

    // ---------------- EVENTOS (pista de auditoria) ----------------
    event Firmado(address indexed firmante, bytes32 hashTerminos, uint64 fecha);
    event Financiado(address indexed importador, uint256 monto);
    event TransitoIniciado(address indexed transportista, uint64 fecha);
    event LecturaTemperatura(address indexed oraculo, int16 decimas, bool excede, uint32 numero);
    event Entregado(address indexed transportista, uint64 fecha);
    event PagoLiberado(address indexed exportador, uint256 monto);
    event DisputaAbierta(address indexed quienAbre);
    event Voto(address indexed arbitro, bool aFavorImportador);
    event Reembolsado(address indexed importador, uint256 monto);
    event Cancelado(address indexed quien);

    // ---------------- PROTECCION CONTRA REENTRADA ----------------
    bool private bloqueado;
    modifier noReentrante() {
        require(!bloqueado, "Reentrada");
        bloqueado = true;
        _;
        bloqueado = false;
    }

    modifier soloEn(Estado esperado) {
        require(estado == esperado, "Estado invalido para esta operacion");
        _;
    }

    constructor(
        PagoToken _token,
        address _exportador,
        address _importador,
        address _transportista,
        address _oraculo,
        address[3] memory _arbitros,
        string memory _producto,
        uint32 _cantidadCajas,
        uint256 _precio,
        int16 _temperaturaMaxDecimas,
        uint64 _fechaLimiteEntrega
    ) {
        require(address(_token) != address(0), "Token invalido");
        require(_exportador != address(0) && _importador != address(0), "Partes invalidas");
        require(_exportador != _importador, "Las partes deben ser distintas");
        require(_transportista != address(0) && _oraculo != address(0), "Roles invalidos");
        require(_precio > 0 && _cantidadCajas > 0, "Terminos invalidos");
        require(_fechaLimiteEntrega > block.timestamp, "Plazo invalido");

        for (uint8 i = 0; i < 3; i++) {
            address a = _arbitros[i];
            require(a != address(0), "Arbitro invalido");
            require(a != _exportador && a != _importador, "Arbitro con conflicto de interes");
            require(!esArbitro[a], "Arbitro repetido");
            esArbitro[a] = true;
        }

        token = _token;
        exportador = _exportador;
        importador = _importador;
        transportista = _transportista;
        oraculo = _oraculo;
        arbitros = _arbitros;
        producto = _producto;
        cantidadCajas = _cantidadCajas;
        precio = _precio;
        temperaturaMaxDecimas = _temperaturaMaxDecimas;
        fechaLimiteEntrega = _fechaLimiteEntrega;
        maximaTemperaturaDecimas = type(int16).min;

        hashTerminos = keccak256(
            abi.encode(
                address(_token), _exportador, _importador, _producto,
                _cantidadCajas, _precio, _temperaturaMaxDecimas, _fechaLimiteEntrega
            )
        );
        estado = Estado.Creado;
    }

    // =======================================================================
    // FUNCIONES (operaciones)
    // =======================================================================

    /// @notice Firma digital: cada parte envia una transaccion firmada con su llave privada
    ///         confirmando el hash exacto de los terminos. Al firmar ambas, el acuerdo inicia.
    function firmar(bytes32 _hashTerminos) external soloEn(Estado.Creado) {
        require(msg.sender == exportador || msg.sender == importador, "Solo las partes firman");
        require(_hashTerminos == hashTerminos, "El hash no coincide con los terminos");
        require(!firmo[msg.sender], "Ya firmo");

        firmo[msg.sender] = true;
        fechaFirma[msg.sender] = uint64(block.timestamp);
        emit Firmado(msg.sender, _hashTerminos, uint64(block.timestamp));

        if (firmo[exportador] && firmo[importador]) {
            estado = Estado.Firmado;
        }
    }

    /// @notice El importador deposita el pago en garantia (requiere approve previo del token).
    function depositarPago() external soloEn(Estado.Firmado) noReentrante {
        require(msg.sender == importador, "Solo el importador");
        require(block.timestamp < fechaLimiteEntrega, "Plazo vencido");
        estado = Estado.Financiado;
        require(token.transferFrom(msg.sender, address(this), precio), "Fallo la transferencia");
        emit Financiado(msg.sender, precio);
    }

    /// @notice El transportista confirma el retiro de la carga.
    function iniciarTransito() external soloEn(Estado.Financiado) {
        require(msg.sender == transportista, "Solo el transportista");
        estado = Estado.EnTransito;
        emit TransitoIniciado(msg.sender, uint64(block.timestamp));
    }

    /// @notice Entrada del ORACULO: lectura de temperatura del contenedor (dato del mundo real).
    function reportarTemperatura(int16 decimas) external {
        require(msg.sender == oraculo, "Solo el oraculo autorizado");
        require(estado == Estado.EnTransito, "Solo durante el transito");

        ultimaTemperaturaDecimas = decimas;
        if (decimas > maximaTemperaturaDecimas) maximaTemperaturaDecimas = decimas;
        totalLecturas += 1;

        bool excede = decimas > temperaturaMaxDecimas;
        if (excede) incumplimientoTermico = true;
        emit LecturaTemperatura(msg.sender, decimas, excede, totalLecturas);
    }

    /// @notice El transportista registra la entrega en destino.
    function registrarEntrega() external soloEn(Estado.EnTransito) {
        require(msg.sender == transportista, "Solo el transportista");
        estado = Estado.Entregado;
        fechaEntrega = uint64(block.timestamp);
        emit Entregado(msg.sender, uint64(block.timestamp));
    }

    /// @notice El importador acepta la carga: libera el pago. Solo si la cadena de frio se cumplio.
    function confirmarRecepcion() external soloEn(Estado.Entregado) noReentrante {
        require(msg.sender == importador, "Solo el importador");
        require(!incumplimientoTermico, "Hubo incumplimiento termico: abra disputa");
        _liberarPago();
    }

    /// @notice Si el importador no responde en 3 dias y no hubo incumplimiento, el exportador cobra.
    function reclamarPago() external soloEn(Estado.Entregado) noReentrante {
        require(msg.sender == exportador, "Solo el exportador");
        require(!incumplimientoTermico, "Hubo incumplimiento termico: abra disputa");
        require(block.timestamp >= fechaEntrega + PLAZO_CONFIRMACION, "Plazo de confirmacion vigente");
        _liberarPago();
    }

    /// @notice Si vencio la fecha limite sin entrega, el importador recupera su dinero.
    function reclamarReembolso() external noReentrante {
        require(msg.sender == importador, "Solo el importador");
        require(estado == Estado.Financiado || estado == Estado.EnTransito, "Estado invalido");
        require(block.timestamp > fechaLimiteEntrega, "Aun hay plazo");
        _reembolsar();
    }

    /// @notice Cualquiera de las partes abre una disputa (carga entregada con problemas o en transito).
    function abrirDisputa() external {
        require(msg.sender == importador || msg.sender == exportador, "Solo las partes");
        require(estado == Estado.Entregado || estado == Estado.EnTransito, "Estado invalido");
        estado = Estado.EnDisputa;
        emit DisputaAbierta(msg.sender);
    }

    /// @notice Gobernanza (mini-DAO): cada arbitro vota una sola vez. Mayoria simple (2 de 3) resuelve.
    function votar(bool aFavorImportador) external soloEn(Estado.EnDisputa) noReentrante {
        require(esArbitro[msg.sender], "Solo arbitros");
        require(!yaVoto[msg.sender], "Ya voto");
        yaVoto[msg.sender] = true;
        if (aFavorImportador) votosImportador += 1; else votosExportador += 1;
        emit Voto(msg.sender, aFavorImportador);

        if (votosImportador >= 2) {
            _reembolsar();
        } else if (votosExportador >= 2) {
            _liberarPago();
        }
    }

    /// @notice Antes de financiar, cualquiera de las partes puede cancelar el acuerdo.
    function cancelar() external {
        require(msg.sender == exportador || msg.sender == importador, "Solo las partes");
        require(estado == Estado.Creado || estado == Estado.Firmado, "Ya esta financiado");
        estado = Estado.Cancelado;
        emit Cancelado(msg.sender);
    }

    // ---------------- Consulta ----------------
    function saldoEnGarantia() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // ---------------- Internas (patron checks-effects-interactions) ----------------
    function _liberarPago() internal {
        estado = Estado.Pagado;
        require(token.transfer(exportador, precio), "Fallo el pago");
        emit PagoLiberado(exportador, precio);
    }

    function _reembolsar() internal {
        estado = Estado.Reembolsado;
        require(token.transfer(importador, precio), "Fallo el reembolso");
        emit Reembolsado(importador, precio);
    }
}
