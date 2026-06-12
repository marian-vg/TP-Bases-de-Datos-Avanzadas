import type { ReactNode } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardAction } from '@/components/ui/card'
import { ScrollArea } from '@/components/ui/scroll-area'
import { cn } from '@/lib/utils'

type DashboardPanelProps = {
  title: string
  description?: string
  action?: ReactNode
  children: ReactNode
  className?: string
  contentClassName?: string
  scroll?: boolean
}

export default function DashboardPanel({
  title,
  description,
  action,
  children,
  className,
  contentClassName,
  scroll = false,
}: DashboardPanelProps) {
  const content = (
    <CardContent className={cn('min-h-0', contentClassName)}>
      {children}
    </CardContent>
  )

  return (
    <Card
      className={cn(
        'hud-panel border bg-white/90 shadow-[0_18px_50px_-34px_rgba(15,23,42,0.45)] backdrop-blur-sm',
        className,
      )}
    >
      <CardHeader className="border-b border-slate-200/70 px-3 py-2.5">
        <div>
          <CardTitle className="text-[13px] font-semibold text-slate-900">{title}</CardTitle>
          {description ? (
            <CardDescription className="mt-0.5 line-clamp-2 text-[11px] leading-4 text-slate-500">{description}</CardDescription>
          ) : null}
        </div>
        {action ? <CardAction>{action}</CardAction> : null}
      </CardHeader>
      {scroll ? (
        <ScrollArea className="min-h-0 flex-1">
          {content}
        </ScrollArea>
      ) : (
        content
      )}
    </Card>
  )
}
