export function formatFeedMessage(message: string, state: any): string {
  if (!message) return ''
  let text = message

  // 1) Traducir e integrar nombres de zonas a partir de IDs numéricos: "zona X" -> "zona [Nombre]"
  if (state?.zonas) {
    const zoneRegex = /\bzona\s*:?\s*(\d+)\b/gi
    text = text.replace(zoneRegex, (match, zoneIdStr) => {
      const zoneId = parseInt(zoneIdStr, 10)
      const zoneObj = state.zonas.find((z: any) => z.id_zona === zoneId)
      return zoneObj ? `zona ${zoneObj.nombre}` : match
    })
  }

  // 2) Traducir "Asignación A[ID]" o "Asignación [ID]" por el nombre descriptivo del recurso asignado
  if (state?.recursos) {
    const assignRegex = /\bAsignaci[oó]n\s+A?(\d+)\b/gi
    text = text.replace(assignRegex, (match, assignIdStr) => {
      const assignId = parseInt(assignIdStr, 10)
      let resourceId = assignId // Fallback: asumir id_recurso == id_asignacion
      
      const activeAssign = state.asignacionesActivas?.find((a: any) => a.id_asignacion === assignId)
      if (activeAssign) {
        resourceId = activeAssign.fk_recurso_id
      }

      const recursoObj = state.recursos.find((r: any) => r.id_recurso === resourceId)
      return recursoObj ? `${recursoObj.tipo_recurso} #${recursoObj.id_recurso}` : match
    })

    // También traducir "recurso [ID]" por su nombre descriptivo
    const resourceRegex = /\brecurso\s+(\d+)\b/gi
    text = text.replace(resourceRegex, (match, resIdStr) => {
      const resId = parseInt(resIdStr, 10)
      const recursoObj = state.recursos.find((r: any) => r.id_recurso === resId)
      return recursoObj ? `${recursoObj.tipo_recurso} #${recursoObj.id_recurso}` : match
    })
  }

  // 3) Simplificar los mensajes operativos típicos del despachador
  // "X viaja de zona Y a zona Z." -> "X viaja hacia la zona Z."
  text = text.replace(/(.+?)\s+viaja\s+de\s+zona\s+(.+?)\s+a\s+zona\s+(.+?)(?=\.|$)/gi, '$1 viaja hacia la zona $3')
  
  // "X llegó a zona Y." -> "X llegó a la zona Y."
  text = text.replace(/(.+?)\s+lleg[oó]\s+a\s+zona\s+(.+?)(?=\.|$)/gi, '$1 llegó a la zona $2')
  
  // "X cerró la atención en zona Y." -> "X finalizó atención en la zona Y."
  text = text.replace(/(.+?)\s+cerr[oó]\s+la\s+atenci[oó]n\s+en\s+zona\s+(.+?)(?=\.|$)/gi, '$1 finalizó atención en la zona $2')

  return text
}
