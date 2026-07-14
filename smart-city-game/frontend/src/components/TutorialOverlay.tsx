import { useState, useEffect } from 'react'
import { Sparkles, ChevronRight, Check } from 'lucide-react'

type TutorialOverlayProps = {
  selectedCatastrophe: string | null
  selectedZoneId: number | null
  onClose: () => void
}

export default function TutorialOverlay({ selectedCatastrophe, selectedZoneId, onClose }: TutorialOverlayProps) {
  const [step, setStep] = useState<number>(0)

  // Avanzar contextualmente del Paso 1 al Paso 2 cuando se arma una catástrofe
  useEffect(() => {
    if (step === 1 && selectedCatastrophe !== null) {
      setStep(2)
    }
  }, [selectedCatastrophe, step])

  // Avanzar del Paso 2 al Paso 3 cuando se selecciona una zona con una catástrofe seleccionada
  useEffect(() => {
    if (step === 2 && selectedZoneId !== null) {
      setStep(3)
    }
  }, [selectedZoneId, step])

  const finishTutorial = () => {
    localStorage.setItem('smartcity_tutorial_completed', 'true')
    onClose()
  }

  // Modificar clases del DOM en caliente para lograr el efecto de foco de neón
  useEffect(() => {
    const removeFocusClasses = () => {
      document.querySelector('.game-hotbar')?.classList.remove('tutorial-highlight-focus')
      document.querySelector('.game-map-area')?.classList.remove('tutorial-highlight-focus')
      document.querySelector('.game-sidebar')?.classList.remove('tutorial-highlight-focus')
    }

    removeFocusClasses()

    if (step === 1) {
      document.querySelector('.game-hotbar')?.classList.add('tutorial-highlight-focus')
    } else if (step === 2) {
      document.querySelector('.game-map-area')?.classList.add('tutorial-highlight-focus')
    } else if (step === 3) {
      document.querySelector('.game-sidebar')?.classList.add('tutorial-highlight-focus')
    }

    return () => removeFocusClasses()
  }, [step])

  if (step === 0) {
    return (
      <>
        <div className="tutorial-backdrop-dim" />
        <div className="tutorial-modal">
          <div className="tutorial-modal-header">
            <div className="tutorial-modal-icon">
              <Sparkles size={18} />
            </div>
            <div className="tutorial-modal-title">¡Bienvenido a Smart City!</div>
          </div>
          <div className="tutorial-modal-body">
            <p>
              Este es un juego que aprovecha la <strong>base de datos activa</strong> desarrollada para Smart City, el cual permite evaluar cómo funciona la base de datos en tiempo real.
            </p>
            <p>
              Como <strong>"Director del Caos"</strong>, tu objetivo es simular catástrofes y ver cómo el despachador inteligente y los recursos (Bomberos, Policías, Ambulancias) se coordinan para resolverlas.
            </p>
            <p>
              Hagamos una guía rápida de <strong>3 pasos</strong> para entender cómo operar los tableros.
            </p>
          </div>
          <div className="tutorial-modal-footer">
            <button className="sim-btn" onClick={onClose} style={{ opacity: 0.7 }} type="button">Saltar</button>
            <button className="sim-btn sim-btn--primary" onClick={() => setStep(1)} style={{ gap: 4 }} type="button">
              Comenzar Guía <ChevronRight size={12} />
            </button>
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      {step === 1 && (
        <div className="tutorial-tooltip tutorial-tooltip--hotbar">
          <div className="tutorial-tooltip-step">Paso 1 de 3</div>
          <div className="tutorial-tooltip-title">Seleccioná una Catástrofe</div>
          <div className="tutorial-tooltip-msg">
            Hacé click en cualquiera de las catástrofes de abajo para armar tu ataque. Por ejemplo, hacé click en <strong>Incendio</strong> o <strong>Falla Estructural</strong>.
          </div>
        </div>
      )}

      {step === 2 && (
        <div className="tutorial-tooltip tutorial-tooltip--map">
          <div className="tutorial-tooltip-step">Paso 2 de 3</div>
          <div className="tutorial-tooltip-title">Inyectá en el Mapa</div>
          <div className="tutorial-tooltip-msg">
            ¡Perfecto! Tenés la catástrofe armada. Ahora <strong>hacé click sobre cualquier zona del mapa</strong> (los nodos con círculos) para inyectar el evento y desatar la respuesta.
          </div>
          <div className="tutorial-tooltip-footer">
            <button className="sim-btn" onClick={() => setStep(1)} style={{ fontSize: 10, padding: '4px 10px' }} type="button">Atrás</button>
          </div>
        </div>
      )}

      {step === 3 && (
        <div className="tutorial-tooltip tutorial-tooltip--sidebar">
          <div className="tutorial-tooltip-step">Paso 3 de 3</div>
          <div className="tutorial-tooltip-title">Ficha Operativa y Recursos</div>
          <div className="tutorial-tooltip-msg">
            ¡Excelente! La zona fue atacada. A la derecha tenés la <strong>Ficha Operativa</strong> de la zona. 
            Acá podés monitorear los incidentes activos, el arribo de recursos y las revisiones pendientes del operador.
          </div>
          <div className="tutorial-tooltip-footer">
            <button className="sim-btn sim-btn--primary" onClick={finishTutorial} style={{ gap: 4, fontSize: 10, padding: '4px 10px' }} type="button">
              <Check size={10} /> Entendido, ¡a jugar!
            </button>
          </div>
        </div>
      )}
    </>
  )
}
