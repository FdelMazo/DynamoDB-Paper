# Dynamo: Amazon's highly available key-value store
![](./img/dynamodb.png)

## Motivación
- Query model
- Propiedades ACID
- Eficiencia
- Otras asunciones

::: notes
Muchos servicios dentro de Amazon tienen ciertos requisitos para los cuales una DB relacional esta lejos de ser ideal. Por complejidad, costo de mantenimiento, decisiones de diseño.

Utilizan items unívocamente identificados por una clave, haciendo operaciones simples de lectura y escritura. Las operaciones se hacen sobre elementos individuales y no hay necesidad de un esquema relacional.

La experiencia en Amazon demuestra que los almacenamientos de datos que proveen garantías ACID tienden a proveer una disponibilidad pobre. Dynamo se enfoca en aplicaciones que operan con consistencia mas débil si esto resulta en una disponibilidad mas alta. No provee ninguna garantía de aislamiento.

El sistema se diseño en base a la necesidad de ser ejecutado sobre hardware commodity, con requisitos de latencia medidos en el percentil 99.9 de la distribución. Los servicios deben poder configurar Dynamo de modo tal que puedan alcanzar sus requisitos de latencia y throughput.

El entorno se asume como no-hostil y no hay requisitos de seguridad.
:::

## SLA y Problemas de negocio
- 99.9th percentile
- Lógica liviana

::: notes
En Amazon, los SLAs se expresan medidos sobre el percentil 99.9, basados en un análisis de costo beneficio.

La mayoría de los servicios de amazon tienen una lógica liviana, por tanto los sistemas de almacenamiento juegan un rol importante ene establecer su SLA. El componente principal de un sistema se vuelve el manejo del estado. Una de las consideraciones principales de Dynamo es permitir que los servicios tengan control sobre las propiedades del sistema, como durabilidad y consistencia, y dejar que decidan sobre los tradeoffs entre funcionalidad, performance y relación costo-beneficio.
:::

## Consideraciones de diseño
- Data store eventualmente consistente
- Resolución de conflictos
- Always writable

::: notes
Dynamo esta diseñado para ser un data store eventualmente consistente: todas las actualizaciones llegan a todas las replicas eventualmente.

Una consideración importante es cuando realizar el proceso de resolución de conflictos de actualización. También el quien: el data store o la aplicación. El data store tiene opciones limitadas, se utiliza una sencilla como "gana la ultima escritura". Las aplicaciones conocen mejor el esquema de datos.

Se orienta al espacio de diseño de un data store siempre disponible para escrituras.
:::

### Principios clave
- Escalabilidad incremental
- Simetría
- Decentralización
- Heterogeneidad

::: notes
Otros principios de diseño:
Escalabilidad incremental: Dynamo debe poder escalar de a un nodo, con mínimo impacto en operaciones tanto del sistema como de operadores del sistema.
Simetría: Todos los nodos de Dynamo deben tener el mismo conjunto de responsabilidades que sus pares. Esto simplifica el proceso de aprovisionamiento y mantenimiento.
Decentralización: es una extension de la simétrica, el diseño debe favorecer técnicas descentralizadas par-a-par por sobre un control centralizado.
Heterogeneidad: El sistema debe ser capaz de explotar la heterogeneidad de la infraestructura sobre la que corre.
:::

# Arquitectura de Sistema

- empezar con la sección 3.3

![](./img/architecture.png)

::: notes

This is my note.

- It can contain Markdown
- like this list

:::

## Interfaz

## Particionado

## Replicado

![](./img/replication.png)

- El coordinador replica a los N-1 siguientes nodos del anillo

- Todos los nodos conocen las responsabilidades del resto

- Los datos se distribuyen en nodos físicos, no virtuales

## Versionado de datos

- Consistencia _eventual_ -> Si opero *YA*, genero una inconsistencia entre nodos
  - Es como git: No quiero perder datos nunca. Cómo reconcilio las distintas versiones?
  - Cada versión es un Vector Clock -> `(nodo, contador)`

- Syntactic Reconciliation: Si una versión nueva supera la antigua, simplemente la reemplaza
- Semantic Reconciliation: Si no hay manera obvia de elegir la versión superadora, el
  cliente decide acorde a sus necesidades de negocio
    - Reglas de negocio -> _Shopping Cart_
    - "Last Write Wins" -> _Session Info_
    - High Performance Read Engine -> _Product Catalog_

![](./img/versioning.png)

## Manejo de fallas: Hinted Handoff
### _Sloppy_ Quorum

::: notes
Si Dynamo usara un enfoque tradicional de quorum, no podría estar disponible durante fallas de servidores o particiones de red. Su durabilidad seria reducida incluso bajo las condiciones mas simples de fallo. Por ello no enfuerza membresía estricta de quorum, usa sloppy quorum: todas las operaciones de lectura y escritura se hacen en los primeros N nodos funcionales de la lista de preferencia. No necesariamente son los primeros N encontrados moviéndose por el anillo de hashing.

:::

### Data center failure

::: notes
Un sistema de almacenamiento altamente disponible tiene que ser capaz de manejar fallas de un data center entero. Dados cortes de electricidad, de enfriamiento, red o desastres naturales.
:::

- Replication across multiple data centers

::: notes
La lista de preferencia de una clave se construye de modo tal que los nodos de almacenamiento se distribuyen en varios data centers conectados por enlaces de alta velocidad.
:::

## Manejo de fallas permanentes: Sincronización de réplicas
- Fallas momentáneas

::: notes
Hinted handoff funciona mejor cuando el churn de membresía del sistema es bajo (es decir, se mantienen dentro del mismo) y las fallas de nodos son momentáneas.
:::

- Protocolo anti-entropía

::: notes
Dynamo implementa un protocolo anti entropía para mantener las replicas sincronizadas, utilizando arboles Merkle para detectar inconsistencias entre replicas mas rápidamente y minimizar la cantidad de data transferida. Cada nodo mantiene un árbol Merkle para cada rango de claves (el set de claves cubiertas por un nodo virtual) que almacena. Permitir que los nodos puedan comparar si las claves dentro de un rango esta actualizadas. Si no, recorren el árbol y y sincronizan adecuadamente. La desventada es que muchas claves cambian cuando un nodo se une o deja el sistema, requiriendo que los arboles se recalculen.
:::

## Membresía y Detección de fallas: Pertenencia al anillo
- Mecanismo explicito

::: notes
Las fallas de nodos en Amazon suelen ser momentáneas (fallas o tareas de mantenimiento) y raramente significan una salida permanente. Por tanto, no amerita rebalancear la asignación de particiones o reparación de las replicas que no se pueden alcanzar.

Por esto, se utiliza un mecanismo explicito para inicia la adición y remoción de nodos de un anillo de Dynamo. UN administrador usa una CLI o el navegador para conectarse a un nodo de Dynamo y enviar un cambio de membresía para unirlo a un anillo o removerlo de un anillo.
:::

- Gossip based protocol

::: notes
Un protocolo basado en rumores propaga los cambios de membresía y mantiene una vista eventualmente consistente de membresía. Cada nodo contacta un par elegido al azar cada segundo y los dos nodos reconcilian cambios persistidos de historial de cambios de membresía.
:::

- Startup

::: notes
Cuando un nodo arranca, elige su set de tokens (nodos virtuales en el espacio de hashing consistente) y hace un mapa de nodos a sus token sets. Los mapas de cada nodo se reconcilian durante el mismo intercambio que reconcilia historiales de cambios de membresía. Esto significa que la información de particionado y ubicación también se propagan con el protocolo basado en rumores y cada nodo de almacenamiento esta al tanto de los rangos de tokens que manejan sus pares. Esto permite que cada nodo pueda forwardear una operación de lectura/escritura al conjunto correcto de nodos directamente.
:::

## Membresía y Detección de fallas: Descubrimiento externo
- Anillo lógicamente particionado

::: notes
Una consecuencia de lo que hablamos recién es que dos nodos pueden considerarse miembros del anillo, y sin embargo ninguno estar al tanto inmediatamente del otro. Para evitar particionados lógicos, algunos nodos de Dynamo tienen el rol de semillas: nodos que se descubren por un mecanismo externo y son conocidos por todos los nodos. Todos los nodos eventualmente reconcilian su membresía con una semilla, entonces los particionados lógicos son altamente improbables. Las semillas se pueden obtener de una configuración estática o de un servicio de configuración. Típicamente son nodos funcionales del anillo de Dynamo.
:::

## Membresía y Detección de fallas: Detección de fallas
- Evitar intentos fallidos de comunicación

::: notes
En dynamo se utiliza la detección de fallas para evitara intentos de comunicarse con pares no alcanzables durante operaciones de get/put o cuando transfiriendo particiones y hinted replicas. Para evitar comunicaciones fallidas, una noción puramente local de detección de fallas alcanza, utilizando nodos alternativos para servir requests de nodos que se detectan que no responden. Cada tanto, se reintenta a los nodos que no responden. En la ausencia de requests de clientes que generen trafico entre ambos nodos, no necesitan saber si el otro es alcanzable y responde.
:::

- Protocolo de rumores

::: notes
Los protocolos descentralizados de detección de fallas utilizan un protocolo sencillo basado en rumores que permite que cada nodo en el sistema aprenda sobre la llegada o salida de los otros nodos.
:::

## Agregando y removiendo nodos de almacenamiento
- Asignación de tokens

::: notes
Cuando un nodo se agrega al sistema, se le asigna una cantidad de tokens distribuidos al azar en el anillo. Por cada rango de claves que se le asigna al nodo, puede haber una cantidad de nodos menor o igual a N que actualmente manejan las claves que caen dentro de ese rango. Dada la asignación de rangos de claves al nuevo nodo, algunos nodos existentes no tienen mas algunas de sus claves y deben transferirlas al nuevo nodo.

Cuando un nodo se elimina del sistema, la resignación de claves sucede en un proceso inverso.
:::

- Distribución uniforme en los nodos

::: notes
La experiencia operativa demuestra que este enfoque distribuye la carga de claves uniformemente entre los nodos de almacenamiento. Esto permite cumplir los requisitos de latencia y bootstrapping rápido.
:::

- Confirmation round
::: notes
Una ronda de confirmación enter el origen y el destino, se asegura que el nodo de destino no reciba ningún duplicado para un dado rango de claves.
:::

## Handlear errores
