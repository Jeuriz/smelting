# 🔥 Sistema de Fundición QBCore

Un sistema completo de fundición para servidores FiveM QBCore con interfaz moderna, sistema de habilidades y características avanzadas.

## 📋 Características

### 🎯 Funcionalidades Principales
- **Sistema de Slots con Habilidades**: 5 slots desbloqueables mediante el sistema de skills
- **Interfaz Moderna**: UI HTML/CSS/JS responsive y atractiva
- **Múltiples Ubicaciones**: Soporte para múltiples hornos en el mapa
- **Sistema de Combustible**: Diferentes tipos de combustible con eficiencias variables
- **Procesamiento Asíncrono**: Los procesos continúan aunque el jugador se desconecte
- **Sistema Anti-Abuse**: Validaciones exhaustivas para prevenir explotación
- **Cache Inteligente**: Optimización de rendimiento con sistema de cache

### 🛠️ Características Técnicas
- **Persistencia de Datos**: Los procesos se mantienen activos entre reconexiones
- **Validación en Tiempo Real**: Verificación continua de inventario
- **Tooltips Informativos**: Ayuda contextual para el usuario
- **Notificaciones Elegantes**: Sistema de notificaciones con ox_lib
- **Progreso Visual**: Barra de progreso con animaciones
- **Responsive Design**: Interfaz adaptable a diferentes resoluciones

## 📦 Dependencias

### Requeridas
```
qb-core
tgiann-inventory
ox_lib
ox_target
devhub_skillTree
```

### Opcionales
```
ox_mysql (para persistencia de datos avanzada)
```

## 🚀 Instalación

### 1. Descarga e Instalación
```bash
# Clonar o descargar el recurso
cd resources/[custom]
git clone [tu-repositorio] smelting-system
```

### 2. Configuración de Dependencias
Asegúrate de que las siguientes dependencias estén instaladas y funcionando:
- `qb-core`
- `tgiann-inventory`
- `ox_lib`
- `ox_target`
- `devhub_skillTree`

### 3. Configuración del server.cfg
```cfg
ensure qb-core
ensure tgiann-inventory
ensure ox_lib
ensure ox_target
ensure devhub_skillTree
ensure smelting-system
```

### 4. Configuración de la Base de Datos
El sistema utiliza el inventario existente, no requiere tablas adicionales.

## ⚙️ Configuración

### Ubicaciones de Hornos
```lua
Config.SmeltingLocations = {
    {x = 2920.90, y = 2653.55, z = 43.18}, -- Puerto de Los Santos
    -- Agregar más ubicaciones aquí
}
```

### Sistema de Habilidades
```lua
Config.SlotSkills = {
    [1] = nil,           -- Slot 1: Siempre disponible
    [2] = "fun_2",       -- Slot 2: Requiere habilidad fun_2
    [3] = "fun_3",       -- Slot 3: Requiere habilidad fun_3
    [4] = "fun_4",       -- Slot 4: Requiere habilidad fun_4
    [5] = "fun_5"        -- Slot 5: Requiere habilidad fun_5
}
```

### Reglas de Fundición
```lua
Config.SmeltingRules = {
    ['mena_aluminio'] = {
        result = 'mena_esmeralda',  -- Producto resultado
        amount = 1,                  -- Cantidad por material
        time = 5000,                -- Tiempo en milisegundos
        fuel_needed = 1             -- Combustible necesario
    },
    -- Agregar más materiales...
}
```

### Combustibles
```lua
Config.FuelItems = {
    'wood',         -- Combustible básico
    'mena_carbon',  -- Combustible avanzado
}
```

## 🎮 Uso del Sistema

### Para Jugadores

#### 1. Acceso al Horno
- Dirígete a cualquier ubicación de horno marcada en el mapa
- Usa `ox_target` para interactuar con el horno
- Selecciona "Usar Horno Grande"

#### 2. Proceso de Fundición
1. **Seleccionar Combustible**: Haz clic en el slot de combustible y elige el tipo
2. **Ajustar Cantidad**: Usa los controles +/- para establecer la cantidad de combustible
3. **Seleccionar Materiales**: Haz clic en los materiales disponibles para fundición
4. **Configurar Cantidades**: Ajusta la cantidad de cada material
5. **Iniciar Proceso**: Haz clic en "FUNDIR" para comenzar

#### 3. Monitoreo del Progreso
- Una barra de progreso aparecerá mostrando el estado del proceso
- El proceso continúa aunque te desconectes del servidor
- Al completarse, recibirás los materiales automáticamente

### Para Administradores

#### Comandos de Debug
```
/smeltdebug - Muestra información de debug del sistema (solo admins)
```

#### Logs del Sistema
El sistema genera logs detallados para:
- Inicio y finalización de procesos
- Detección de intentos de abuso
- Errores de inventario
- Reconexiones de jugadores con procesos activos

## 🔧 Personalización

### Modificar Estilos
Edita `html/style.css` para personalizar:
- Colores de la interfaz
- Fuentes y tipografías
- Animaciones y efectos
- Layout y disposición

### Agregar Nuevos Materiales
1. Edita `config.lua` en la sección `SmeltingRules`
2. Agrega las imágenes correspondientes en `tgiann-inventory/html/images/`
3. Reinicia el recurso

### Modificar Textos
Todos los textos están centralizados en `Config.Texts` para fácil traducción:
```lua
Config.Texts = {
    ['open_smelting'] = 'Usar Horno Grande',
    ['smelting_complete'] = '¡Proceso de fundición completado!',
    -- Más textos...
}
```

## 🛡️ Características de Seguridad

### Sistema Anti-Abuse
- **Validación de Inventario**: Verificación continua de materiales
- **Cooldown de Procesos**: Previene spam de inicios de proceso
- **Verificación de Skills**: Validación de habilidades requeridas
- **Logs de Seguridad**: Registro de intentos de abuso

### Optimización
- **Cache de Items**: Sistema de cache para reducir consultas
- **Limpieza Automática**: Limpieza periódica de datos temporales
- **Callbacks Optimizados**: Uso eficiente de ox_lib callbacks

## 🐛 Solución de Problemas

### Problemas Comunes

#### El horno no aparece en el mapa
```lua
-- Verificar que ox_target esté funcionando
-- Comprobar las coordenadas en Config.SmeltingLocations
```

#### Los items no se procesan
```lua
-- Verificar que tgiann-inventory esté actualizado
-- Comprobar los nombres de items en SmeltingRules
-- Revisar logs del servidor para errores
```

#### Las habilidades no funcionan
```lua
-- Verificar que devhub_skillTree esté funcionando
-- Comprobar los nombres de skills en SlotSkills
-- Verificar que el jugador tenga las habilidades desbloqueadas
```

### Debug y Logs
Para activar debug extendido:
```lua
-- En server/main.lua, cambiar el nivel de logging
print(string.format("^2[Smelting Debug]^7 %s", message))
```

## 📝 Changelog

### Versión 1.0.0
- ✅ Sistema base de fundición
- ✅ Integración con ox_lib y ox_target
- ✅ Sistema de habilidades
- ✅ Interfaz HTML moderna
- ✅ Sistema anti-abuse
- ✅ Persistencia de procesos

## 🤝 Contribución

### Reportar Bugs
Utiliza el sistema de issues para reportar problemas, incluyendo:
- Descripción detallada del problema
- Pasos para reproducir
- Logs del servidor
- Configuración utilizada

### Sugerir Mejoras
Las sugerencias son bienvenidas. Incluye:
- Descripción de la funcionalidad
- Casos de uso
- Implementación sugerida

## 📄 Licencia

Este proyecto está bajo licencia [MIT/Custom] - ver el archivo LICENSE para detalles.

## 🙏 Créditos

- **QBCore Framework**: Base del sistema
- **tgiann-inventory**: Sistema de inventario
- **ox_lib**: Callbacks y notificaciones
- **ox_target**: Sistema de interacciones
- **devhub_skillTree**: Sistema de habilidades

---

**⚠️ Nota**: Este sistema está diseñado para servidores QBCore. Asegúrate de tener todas las dependencias instaladas y configuradas correctamente antes de usar.

**🔧 Soporte**: Para soporte técnico, abre un issue en el repositorio o contacta a través de los canales oficiales.
