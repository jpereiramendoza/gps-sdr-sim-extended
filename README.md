# GPS-SDR-SIM Extended 

Repositorio para el desarrollo del software de GPS-SDR-SIM Extended con implementacion de nuevas funcionalidades como multicamino, ruido gaussiano y recepcion de archivo de parametros, entre otras funcionalidades. 

Este proyecto es un fork de https://github.com/osqzss/gps-sdr-sim el proyecto original. 

## Compilacion del proyecto 

En Linux 

```
make
```

Esto genera el binario `gps-sdr-sim-ext`

Para limpiar los archivos objetos y realizar una nueva compilación

```
make clean
```

## Archivo de parametros (.cfg)

Se realizo una modificacion al programa origina, el parametro `-C` permite entregar un archivo de configuracion (por ejemplo 'config.cfg' ) el cual puede tener los parametros entregado por linea de comando 

Ejemplo de parametros dentro del archivo de configuracion 

```
# archivo: configs/santiago_mp.cfg
# ---------- Parámetros generales (equivalentes a CLI) ----------
eph      = conf/brdc3360.24n
sps      = 2048000
duration = 300
outfile  = data/plaza_armas.bin
llh      = -33.43779346177633,-70.6505034191419,0
tstart   = 2025/08/24,10:20:00
tref     = 2025/08/24,10:20:00
bits     = 8
power    = 128
verbose  = 1
seed     = 12345
```

Esto no reemplaza la linea de comandos normal, la cual se puede seguir utilizando de forma normal. De todas formas, si se requiere usar las nuevas funcionalidades, se debe utilizar un archivo de configuración. 

## Ruido térmico equivalente

El simulador original no incorpora ningún modelo de ruido que represente el efecto térmico del receptor.

En esta versión se añade la posibilidad de activar **ruido térmico global**, configurable mediante el siguiente parámetro en el archivo de configuración:

```
NOISE_SNR 45
```

Este parámetro fija una relación potencia de señal / potencia de ruido de 45 dB en las muestras I/Q generadas.

El ruido se aplica de forma constante sobre toda la señal I/Q, lo que permite emular de manera más realista las condiciones de recepción en un receptor GNSS real.

### Cómo se calcula

El modelo utiliza ruido blanco gaussiano aditivo (AWGN) complejo ajustado al SNR indicado:

- Se estima la potencia media de la señal ideal (sin ruido) sobre una ventana inicial de muestras (por defecto 50.000 muestras):
```  
  P_signal = media( I^2 + Q^2 )
```
- Se convierte el valor de `NOISE_SNR` de dB a escala lineal:
```
  SNR_lin = 10^( NOISE_SNR / 10 )
```
- Se calcula la potencia de ruido objetivo:
```
  P_noise = P_signal / SNR_lin
```
- A partir de `P_noise` se obtiene la desviación estándar del ruido para cada componente (I y Q) del ruido complejo:
```
  sigma = sqrt( P_noise / 2 )
```
- Para cada muestra se generan valores gaussianos con media 0 y desviación sigma que se suman a la señal ideal:
```
  I_out = I_ideal + n_I
  Q_out = Q_ideal + n_Q
```

De este modo, la señal I/Q resultante mantiene aproximadamente la relación señal/ruido especificada en `NOISE_SNR`, emulando el ruido térmico equivalente de un receptor GNSS real.

## Filtro FIR digital (modo baseband)

El simulador incluye un filtro FIR pasa-bajos opcional para modelar el comportamiento del front-end digital de un receptor GNSS real.  
Su objetivo es limitar la banda efectiva de la señal I/Q, reducir aliasing y suavizar el espectro antes de la cuantización final.

### ¿Qué hace el filtro?

- Aplica un filtrado **pasa-bajos** de fase lineal sobre las muestras I/Q.
- Mantiene la integridad temporal del código GNSS (no distorsiona la forma del chip).
- Modela el filtrado digital típico de un front-end GNSS (FIR simétrico).
- Reduce energía fuera de banda y mejora la relación señal-ruido en la banda útil.

### Cómo se implementa

1. El usuario define:
   - Frecuencia de muestreo `fs`
   - Frecuencia de corte `fc`
   - Número de taps `N` (debe ser impar)

2. Al iniciar el programa:
   - Se generan los taps mediante:
     - **sinc recortada** centrada en cero  
     - **ventana Hamming**  
     - **normalización** para obtener ganancia unitaria
   - Estos coeficientes permanecen fijos durante toda la ejecución.

3. Durante la generación de cada muestra:
   - Se mantiene un buffer con las últimas `N` muestras I/Q.
   - La salida filtrada se obtiene con la convolución:
     ```
     y[n] = Σ h[k] · x[n−k]
     ```
   - El resultado reemplaza a la muestra I/Q antes de la cuantización final.

### Detalles importantes

- El filtro solo es válido si se cumple:

```
0 < fc < fs / 2
```
(condición de Nyquist)

- Al ser un FIR simétrico:
- tiene **fase lineal perfecta**, solo introduce retraso fijo  
- no deforma el pico de correlación GNSS  
- es completamente estable (sin realimentación)

- El retardo del filtro es:

```
delay = (N - 1) / 2 muestras
```

- El filtrado se realiza **después del escalamiento AGC inicial** pero **antes de la cuantización final**.


## Implementación de multicamino

El modelo de multicamino se configura mediante una serie de parametros que se listan a continuacion

El objetivo es que se puedea diseñar escenarios realistas de un entorno con multicamino.

### Parámetros de simulación

El archivo de configuración de multicamino define **ecos adicionales** sobre la señal simulada.  

Cada línea describe **un eco** asociado a un satélite. Si se desea más de un eco en el mismo satélite, se agregan varias líneas para ese PRN.


### Reglas generales

- **Cada línea agrega un eco.**  
  Varias líneas con el mismo PRN ⇒ múltiples ecos en ese satélite.
- **Líneas con PRN = 00** ⇒ el simulador selecciona satélites válidos de forma aleatoria, sin repetir.  
- Si se solicitan más ecos de los que se pueden asignar a satélites elegibles,  
  los ecos extra se **ignoran** y se genera un *warning*.
- Las unidades de los parámetros son:
  - `tau_chips` → retardo en **chips**
  - `phase_deg` → fase en **grados**
  - `amp_lin` → amplitud **lineal** relativa a la LOS

Existen tres tipos de líneas:

#### 1. SIM

Define un eco simple y fijo sobre un satélite.  
El retardo, fase y amplitud se mantienen **constantes durante toda la simulación**.  

Es útil para pruebas controladas donde se necesita un eco estable y reproducible.

**Sintaxis:**

```text
SIM <prn> <tau_chips> <phase_deg> <amp_lin>
```

#### 2. ECH

Define un eco de multicamino automático, calculado según la geometría del satélite y el modelo interno.  

La idea es representar un multicamino más “realista”: por ejemplo, un satélite cercano al cenit (≈ 90° sobre el receptor) idealmente no debería presentar multicamino significativo.


Si se requieren varios ecos para el mismo satélite, se repite la línea con el mismo PRN tantas veces como reflejos se necesiten.  

En general, se asume que un reflejo posterior tendrá una amplitud menor que el primero.

Sintaxis:
```
ECH <prn>
```
Donde 
- `<prn>`
  - 00 → seleccionar un satélite aleatorio válido y mantenerlo fijo durante toda la simulación.
  - 01..32 → aplicar al PRN indicado.

El retardo, la fase y la amplitud se calculan internamente.

Ejemplos:
```
ECH 00
ECH 15
```

#### 3. PRN

Fuerza la generación de multicamino sobre un satélite específico, incluso si por geometría ideal no debería tenerlo.  

Por ejemplo, un satélite a 90° sobre el receptor normalmente no tendría multicamino, pero con `PRN` se le pueden asignar uno o más ecos sintéticos (retardo, fase y amplitud generados de forma aleatoria según el modelo interno).


Si se requieren varios ecos en el mismo satélite, se repite la línea.  
Cada eco adicional se suma al anterior, normalmente con menor amplitud.


Sintaxis:
PRN <prn>

Ejemplo:
```
PRN 23
PRN 12
PRN 23 # Este multicamino se suma al anterior, con menor amplitud
```

## Estado actual de la implementación

Actualmente, el simulador implementa:

- Implementacion de archivo Make para compilacion.
- Lectura de archivo de configuración con parametros.
- Implementacion de ruido termico equivalente mediante AWGN
- Interpretación de líneas `SIM`, que permiten definir ecos fijos (retardo, fase y amplitud constantes) por satélite.

Las líneas `ECH` y `PRN` están ya definidas en el formato de configuración, pero su modelo interno todavía está en desarrollo y su efecto puede ser limitado o no estar completamente implementado. Se recomienda, por ahora, utilizar principalmente líneas `SIM` para pruebas y experimentación reproducible.
