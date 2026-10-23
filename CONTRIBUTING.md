# Contributing to SmartGrid-Twin

We welcome contributions to **SmartGrid-Twin**! Whether you are an academic researcher, energy engineer, or open-source software developer, your contributions help make physics-informed AI for renewable energy and smart grids more accessible and robust.

---

## Code of Conduct
We are committed to providing a welcoming and inspiring community for all contributors. Please treat everyone with respect and constructive feedback.

## How Can You Contribute?
1. **Reporting Bugs & Data Anomalies**: Open an issue describing the unexpected behavior, inverter/logger vendor, and reproduction steps.
2. **Adding Inverter / SCADA Vendor Parsers**: Implement parsers in `src/+ges/+io/` for other major manufacturers (e.g., Fronius, SolarEdge, Sungrow, ABB, Schneider).
3. **Enhancing Physics-Informed Models**: Improve transposition (Perez, HDKR), cell temperature models (King, Faiman, Sandia), or inverter loss models.
4. **Expanding Agent Capabilities**: Add new diagnostic agents, domain rules, or multi-modal visual inspection techniques.

## Development Workflow
1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/my-new-feature`.
3. Add your implementation under `src/+ges/` or `app/`.
4. Ensure all unit and regression tests pass by running:
   ```matlab
   setupGes();
   runAllTests();
   ```
5. Commit your changes with clear, descriptive commit messages:
   ```bash
   git commit -m "feat(solar): add Perez diffuse transposition model support"
   ```
6. Push to your branch and open a Pull Request.

## Coding Standards
- Follow standard MATLAB naming conventions and functional modularity (`+package` namespaces).
- Preserve existing comments and docstrings.
- Ensure all public functions include argument validation blocks (`arguments ... end`).
- Exclude all raw datasets, proprietary logs, and personal credentials from commits.
