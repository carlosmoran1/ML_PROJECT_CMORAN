# cookiecutter_data_science_base

Plantilla base para proyectos de Data Science en GitHub, inspirada en la estructura de Cookiecutter Data Science.

## Estructura
```text
cookiecutter_data_science_base/
├── .github/workflows/      # CI opcional
├── config/                 # parámetros y settings
├── data/
│   ├── raw/                # datos originales, sin tocar
│   ├── interim/            # datos intermedios
│   ├── processed/          # datos listos para modelar
│   └── external/           # datos externos o de terceros
├── docs/                   # documentación adicional
├── models/                 # modelos entrenados o serializados
├── notebooks/              # notebooks exploratorios
├── references/             # papers, diccionarios, etc. 
├── test/                   #test
├── reports/
│   └── figures/            # gráficos e imágenes exportadas
├── src/
│   ├── data/               # ingestión / carga de datos
│   ├── features/           # feature engineering
│   ├── models/             # entrenamiento / inferencia
│   └── visualization/      # visualizaciones
├── .gitignore
├── Makefile
├── pyproject.toml
└── requirements.txt
```

## Inicio rápido
```bash
git init
git add .
git commit -m "Estructura inicial Data Science"
```

## Recomendación

- Usar `data/raw/` para datos originales.
- Usar `notebooks/` solo para exploración.
- Pasar la lógica estable a `src/`.

