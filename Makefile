install:
	pip install -r requirements.txt

test:
	pytest -q

run-train:
	python -m src.models.train_model

run-features:
	python -m src.features.build_features
