from pathlib import Path

def main() -> None:
    raw_path = Path("data/raw")
    interim_path = Path("data/interim")
    print(f"Leyendo datos desde: {raw_path}")
    print(f"Guardando datos intermedios en: {interim_path}")

if __name__ == "__main__":
    main()
