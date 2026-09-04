-- ==============================================================================
-- SCHEMA MIGRATION: AutoTakeoff AI (Cómputos Métricos y Presupuestos)
-- Creado para el ecosistema CarMiDev
-- ==============================================================================

-- 1. EXTENSIONES
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. TABLA: proyectos
CREATE TABLE IF NOT EXISTS public.proyectos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    nombre TEXT NOT NULL,
    area_documento_m2 NUMERIC(10, 2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Índices de búsqueda
CREATE INDEX IF NOT EXISTS idx_proyectos_user_id ON public.proyectos(user_id);
CREATE INDEX IF NOT EXISTS idx_proyectos_created_at ON public.proyectos(created_at DESC);

-- 3. TABLA: ambientes (Recintos detectados por la IA en cada nivel del plano)
CREATE TABLE IF NOT EXISTS public.ambientes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proyecto_id UUID NOT NULL REFERENCES public.proyectos(id) ON DELETE CASCADE,
    nivel TEXT NOT NULL DEFAULT 'Planta Baja',
    nombre TEXT NOT NULL,
    area_neta_m2 NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    largo_m NUMERIC(10, 2) DEFAULT 0.00,
    ancho_m NUMERIC(10, 2) DEFAULT 0.00,
    tipo TEXT NOT NULL CHECK (tipo IN ('social', 'bed', 'humedo', 'service', 'exterior')),
    vanos_area_m2 NUMERIC(10, 2) DEFAULT 0.00,
    ancho_puertas_m NUMERIC(10, 2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Índices de relación
CREATE INDEX IF NOT EXISTS idx_ambientes_proyecto_id ON public.ambientes(proyecto_id);
CREATE INDEX IF NOT EXISTS idx_ambientes_tipo ON public.ambientes(tipo);

-- 4. TABLA: tabulador_partidas (Catálogo de rubros y precios unitarios en USD)
CREATE TABLE IF NOT EXISTS public.tabulador_partidas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE, -- NULL indica partidas estándar globales del sistema
    codigo TEXT NOT NULL,
    descripcion TEXT NOT NULL,
    unidad TEXT NOT NULL CHECK (unidad IN ('M2', 'ML', 'SG', 'UND')),
    precio_unitario_usd NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    factor_desperdicio NUMERIC(5, 2) NOT NULL DEFAULT 0.10,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_tabulador_user_id ON public.tabulador_partidas(user_id);
CREATE INDEX IF NOT EXISTS idx_tabulador_codigo ON public.tabulador_partidas(codigo);

-- ==============================================================================
-- POLÍTICAS ROW LEVEL SECURITY (RLS) - SEGURIDAD ESTRICTA
-- ==============================================================================
ALTER TABLE public.proyectos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ambientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tabulador_partidas ENABLE ROW LEVEL SECURITY;

-- Políticas para proyectos
CREATE POLICY "Users can only access their own projects"
    ON public.proyectos
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Políticas para ambientes (a través del proyecto del usuario autenticado)
CREATE POLICY "Users can only access rooms of their own projects"
    ON public.ambientes
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.proyectos p
            WHERE p.id = ambientes.proyecto_id
            AND p.user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.proyectos p
            WHERE p.id = ambientes.proyecto_id
            AND p.user_id = auth.uid()
        )
    );

-- Políticas para tabulador_partidas (Partidas globales o personalizadas del usuario)
CREATE POLICY "Users can read global items or their own custom items"
    ON public.tabulador_partidas
    FOR SELECT
    USING (user_id IS NULL OR user_id = auth.uid());

CREATE POLICY "Users can manage their own custom items"
    ON public.tabulador_partidas
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ==============================================================================
-- SEED DATA: PARTIDAS ESTÁNDAR DE CÓMPUTO Y PRESUPUESTO
-- ==============================================================================
INSERT INTO public.tabulador_partidas (user_id, codigo, descripcion, unidad, precio_unitario_usd, factor_desperdicio)
VALUES
    (NULL, 'REV-01', 'Sobrepiso de nivelación y adecuación de superficie e=4cm', 'M2', 9.50, 0.05),
    (NULL, 'REV-02', 'Suministro y colocación de piso porcelanato en áreas principales', 'M2', 32.00, 0.10),
    (NULL, 'REV-03', 'Suministro y colocación de piso porcelanato antideslizante en baños', 'M2', 36.50, 0.12),
    (NULL, 'PARE-01', 'Suministro y colocación de revestimiento cerámico en paredes húmedas', 'M2', 28.00, 0.10),
    (NULL, 'ROD-01', 'Suministro e instalación de rodapié porcelánico/madera en áreas secas', 'ML', 7.20, 0.08),
    (NULL, 'PINT-01', 'Preparación de fondo, encamisado y pintura de caucho en paredes secas', 'M2', 6.80, 0.05)
ON CONFLICT DO NOTHING;
