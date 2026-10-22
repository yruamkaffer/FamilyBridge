#!/usr/bin/env python3
"""Diagnóstico de engines APS, com paginação. Não inicia WorkItems."""
import sys
from familybridge import main, BridgeError

if __name__ == '__main__':
    try:
        sys.exit(main(['engines']))
    except (BridgeError, ValueError, KeyError, TypeError, OSError) as exc:
        print(str(exc) if isinstance(exc, BridgeError) else 'Resposta APS inválida.', file=sys.stderr)
        sys.exit(2)
