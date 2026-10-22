# Dados, categorias e parâmetros

[Início](../README.md) · [Uso](INSTALACAO_E_USO.md)

## `metadata.json`

Criado automaticamente no pacote local. Exemplo fictício, sem credenciais:

```json
{
  "schema_version": 1,
  "output_name": "Torneira Exemplo.rfa",
  "generator": {"name": "FamilyBridge", "version": "0.8.1", "author": "Yruam Käffer de Faria"},
  "product": {
    "manufacturer": "Fabricante Exemplo",
    "code": "EX-001",
    "name": "Torneira Exemplo",
    "collection": "Linha A",
    "finish": "Cromado",
    "description": "Descrição do produto",
    "website": "https://example.com/produto",
    "category": "Plumbing Fixtures"
  },
  "geometry": {
    "file": "model.step",
    "format": "STEP ISO 10303",
    "unit": "mm",
    "dimensions_mm": {"x": 100.0, "y": 80.0, "z": 150.0}
  },
  "exported_at_utc": "2026-10-22T12:00:00Z"
}
```

O campo `geometry.dimensions_mm` vem dos limites do **SKP** em milímetros. Use o STEP e a família final para validar dimensões do sólido. `output_name` usa o nome do SKP salvo ou, se não houver, código e nome normalizados. Código e nome são obrigatórios; os demais campos de produto podem ficar vazios. O site é copiado como digitado, sem reparo automático da URL.

## Mapeamento do produto

| Campo do painel / JSON | Parâmetro customizado na família | Parâmetro nativo, se editável |
| --- | --- | --- |
| Fabricante / `manufacturer` | `FB_Fabricante` | Manufacturer |
| Código / `code` | `FB_Codigo` | Model |
| Nome / `name` | `FB_Produto` | — |
| Linha / `collection` | `FB_Linha` | — |
| Acabamento / `finish` | `FB_Acabamento` | — |
| Descrição / `description` | `FB_Descricao` | Description |
| Site / `website` | `FB_Site` | URL |
| Categoria / `category` | Categoria da família | — |

Os parâmetros `FB_*` são parâmetros **de família, de texto, por tipo** criados pelo worker. Os nativos são definidos apenas quando o template disponibiliza parâmetros editáveis. Os nomes visíveis dos nativos dependem do idioma do Revit.

| Opção no painel | Identificador JSON | Categoria Revit |
| --- | --- | --- |
| Modelos genéricos | `Generic Models` | `OST_GenericModel` |
| Peças hidráulicas | `Plumbing Fixtures` | `OST_PlumbingFixtures` |
| Equipamentos mecânicos | `Mechanical Equipment` | `OST_MechanicalEquipment` |
| Mobiliário | `Furniture` | `OST_Furniture` |

Escolher uma categoria não cria conectores, regras MEP ou famílias hospedadas.

## `colors.json`

Artefato produzido pelo Fusion e consumido pelo Revit:

```json
{
  "schema_version": 1,
  "bodies": [
    {"dimensions_mm": [100.0, 80.0, 150.0], "volume_mm3": 123456.0, "rgb": [220, 220, 220]}
  ]
}
```

Cada entrada corresponde a um corpo sólido; os valores RGB inteiros vão de 0 a 255. Os nomes `FamilyBridge RGB R-G-B` identificam materiais de cor usados nos elementos. O manifesto não guarda textura, brilho, transparência ou cor por face. Os valores acima são ilustrativos e não descrevem um produto real.
