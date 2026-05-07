# Diagnostico de la diferencia de tiempos en Palisade

La causa principal no era la dimension de las instancias, sino el callback de
conectividad. Dos instancias `10x5` generan el mismo tamano teorico de modelo,
pero no necesariamente el mismo arbol de busqueda. En este caso, ademas, el
callback cortaba solo una componente desconectada por candidata y hacia
`return`; la instancia 2 generaba muchas candidatas enteras desconectadas, asi
que CPLEX pasaba cientos de segundos repitiendo el ciclo:

1. encuentra una candidata entera;
2. el callback la rechaza por estar desconectada;
3. CPLEX sigue buscando otra candidata.

Aplique la correccion en `palisade/src/resolution.jl`: ahora, cuando una region
aparece desconectada, se agregan cortes lazy para todas sus componentes
desconectadas, no solo para la primera.

## Datos clave

| Metrica | `gen_10x5_reg10_1` | `gen_10x5_reg10_2` |
|---|---:|---:|
| Tiempo guardado original | 1.63 s | 687.28 s |
| Celdas con pista | 25 | 36 |
| Aristas pista-pista | 21 | 43 |
| Aristas vacio-vacio | 19 | 4 |
| Modelo reducido final CPLEX | 856 binarias | 1053 binarias |
| Callback original, diagnostico | 994 nodos, 114 cortes | 60 s sin solucion, 18,952 nodos, 100 candidatas desconectadas |
| Callback corregido | ~2.69 s | ~15.15 s |

## Explicacion

La conectividad no esta en el modelo inicial; se impone con lazy constraints.
CPLEX verifica estas restricciones cuando aparece una candidata entera, no
continuamente durante toda la relajacion lineal. Por eso CPLEX puede encontrar
muchas soluciones enteras que cumplen las pistas y los tamanos de region, pero
que todavia tienen regiones desconectadas.

La instancia 1 llega relativamente pronto a una candidata conectada. La instancia
2, en cambio, tiene una estructura de pistas mucho mas densa y deja a CPLEX con
menos reducciones utiles en presolve. Aunque tenga mas pistas, eso no implica que
sea mas facil: puede hacer el espacio factible mas estrecho, mas irregular y
menos guiado para el branch-and-cut.

Tambien hay mucha simetria: las 10 regiones son intercambiables, asi que existen
hasta `10!` etiquetados equivalentes para una misma particion geometrica. Esa
simetria puede multiplicar el numero de ramas equivalentes que explora CPLEX.

## Solucion aplicada

Antes, el callback hacia esencialmente esto:

```julia
W = components[1]
MOI.submit(...)
return
```

Ahora recorre todas las componentes:

```julia
for W in components
    MOI.submit(...)
end
```

Esto hace que una sola candidata desconectada aporte mucha mas informacion al
solver. En la instancia lenta, la corrida real con `cplexSolve` bajo de
`687.28 s` a aproximadamente `15.15 s`.

No actualice los archivos en `palisade/res/cplex/`, porque contienen los
resultados historicos que explican el problema. Para usar la version corregida en
el informe o en las tablas, hay que regenerar esos resultados.

## Fuentes consultadas

- IBM, diferencias entre user cuts y lazy constraints:
  <https://www.ibm.com/docs/en/icos/22.1.1?topic=pools-differences-between-user-cuts-lazy-constraints>
- IBM, `IloCplex::LazyConstraintCallbackI`:
  <https://www.ibm.com/docs/en/icos/22.1.0?topic=classes-ilocplexlazyconstraintcallback>
- IBM, cortes en CPLEX:
  <https://www.ibm.com/docs/en/icos/22.1.1?topic=cuts-what-are>
- IBM, reduccion de simetria en modelos MIP:
  <https://www.ibm.com/docs/es/icos/22.1.2?topic=parameters-symmetry-breaking-mip-models>
- Gurobi, variabilidad de rendimiento:
  <https://support.gurobi.com/hc/en-us/articles/360045849232-Why-does-Gurobi-perform-differently-on-different-machines>
- Gurobi, recomendaciones para fortalecer formulaciones MIP:
  <https://support.gurobi.com/hc/en-us/articles/13793044538001-General-guidelines-to-strengthen-a-MIP-formulation>
